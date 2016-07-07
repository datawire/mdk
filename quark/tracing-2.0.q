quark 1.0;

package datawire_mdk_tracing 2.0.0;

use protocol-1.0.q;
use introspection-1.0.q;

import mdk_protocol;
import mdk_introspection;
import mdk_tracing.protocol;

import quark.concurrent;

@doc("""
Tracing is the log collector for the MDK.

A brief event overview:

- LogEvent carries log messages. Again, there will likely be many of
  these for a given request.

So e.g. if a service named grue-locator gets a request for which it has to
call another service named grue-creator, then you get an event sequence
something like

+00ms grue-locator ctx0 RequestStart grue=bob
+01ms grue-locator ctx0 LogRecord DEBUG Off we go!
+02ms grue-locator ctx0 LogRecord INFO No grue located, creating a new one
+03ms grue-creator ctx0 RequestStart hungry=true
+05ms grue-creator ctx0 LogRecord INFO Creating a new hungry grue!
+08ms grue-creator ctx0 LogRecord DEBUG This grue will be named bob
+08ms grue-creator ctx0 LogRecord DEBUG Allocating bob, who is hungry
+15ms grue-creator ctx0 LogRecord INFO We have bob!
+16ms grue-creator ctx0 RequestEnd success!
+17ms grue-locator ctx0 LogRecord INFO Got a grue named bob!
+20ms grue-locator ctx0 LogRecord DEBUG bob is at 0, 0, 0
+21ms grue-locator ctx0 RecordEnd success!
""")

namespace mdk_tracing {

    class SharedContextInitializer extends TLSInitializer<SharedContext> {
        SharedContext getValue() {
            return null;
            // return new SharedContext();
        }
    }

    class Tracer {
        static Logger logger = new Logger("MDK Tracer");

        String url = "";
            String queryURL = "";

        String token;
        long lastPoll = 0L;

        TLS<SharedContext> _context = new TLS<SharedContext>(new SharedContextInitializer());
        protocol.TracingClient _client;

        Tracer() { }

        static Tracer withURLsAndToken(String url, String queryURL, String token) {
            Tracer newTracer = new Tracer();

            newTracer.url = url;

            if ((queryURL == null) || (queryURL.size() == 0)) {
                URL parsedURL = URL.parse(url);

                if (parsedURL.scheme == "ws") {
                    parsedURL.scheme = "http";
                }
                else {
                    parsedURL.scheme = "https";
                }

                parsedURL.path = "/api/logs";

                newTracer.queryURL = parsedURL.toString();
            }

            newTracer.token = token;

            return newTracer;           
        }

        void _openIfNeeded() {
            if (_client == null) {
                _client = new protocol.TracingClient(self);
            }

            if (token == null) {
                token = DatawireToken.getToken();
            }
        }

        void stop() {
            if (_client != null) {
                _client.stop();
            }
        }

        void initContext() {
            // Implicitly creates a span for you.
            _context.setValue(new SharedContext());
        }

        void joinContext(SharedContext context) {
            _context.setValue(context.start_span());
            // Always open a new span when joining a context.
        }

        void joinEncodedContext(String encodedContext) {
            SharedContext newContext = SharedContext.decode(encodedContext);
            self.joinContext(newContext);
        }

        SharedContext getContext() {
            return _context.getValue();
        }

        void setContext(SharedContext ctx) {
            _context.setValue(ctx);
        }

        void start_span() {
            _context.setValue(self.getContext().start_span());
        }

        void finish_span() {
            _context.setValue(self.getContext().finish_span());
        }

        void log(String procUUID, String level, String category, String text) {
            self._openIfNeeded();

            SharedContext ctx = self.getContext();
            ctx.tick();
            logger.info("CTX " + ctx.toString());

            LogEvent evt = new LogEvent();
            evt.context = ctx;
            evt.timestamp = now();
            evt.node = procUUID;
            evt.level = level;
            evt.category = category;
            evt.contentType = "text/plain";
            evt.text = text;
            _client.log(evt);
        }

        Promise poll() {
            // XXX: this shouldn't really be necessary
            self._openIfNeeded();

            logger.info("Polling for logs...");

            long rightNow = now();
            Promise result = query(lastPoll, rightNow);
            lastPoll = rightNow;
            return result.andThen(bind(self, "deresultify", []));
        }

        List<LogEvent> deresultify(api.GetLogEventsResult result) {
            logger.info("got " + result.result.size().toString() + " log events");
            return result.result;
        }

        @doc("Query the trace logs. startTimeMillis and endTimeMillis are milliseconds since the UNIX epoch.")
        Promise query(long startTimeMillis, long endTimeMillis) {
            // Set up args.
            List<String> args = [];
            String reqID = "Query ";

            if (startTimeMillis >= 0) {
                args.add("startTime=" + startTimeMillis.toString());
                reqID = reqID + startTimeMillis.toString();
            }

            reqID = reqID + "-";

            if (endTimeMillis >= 0) {
                args.add("endTime=" + endTimeMillis.toString());
                reqID = reqID + endTimeMillis.toString();
            }

            // Grab the full URL...

            String url = self.queryURL;

            if (args.size() > 0) {
                url = url + "?" + "&".join(args);
            }

            // Off we go.
            HTTPRequest req = new HTTPRequest(url);

            req.setMethod("GET");
            req.setHeader("Content-Type", "application/json");
            req.setHeader("Authorization", "Bearer " + self.token);

            return IO.httpRequest(req).andThen(bind(self, "handleQueryResponse", []));
        }

        Object handleQueryResponse(HTTPResponse response) {
            int code = response.getCode();      // HTTP status code
            String body = response.getBody();   // just to save keystrokes later

            if (code == 200) {
                // All good. Parse the JSON in the body...
                return api.GetLogEventsResult.decode(body);
            }
            else {
                // Per the HTTP status code, something has gone wrong. Try to pull a
                // sensible error out of the body...
                String error = "";

                if (body.size() > 0) {
                    error = body;
                }

                // In any case, if we have no error, synthesize something from the
                // status code.
                if (error.size() < 1) {
                    error = "HTTP response " + code.toString();
                }

                logger.info("OH NO! " + error);

                return new HTTPError(error);
            } 
        }
    }

    namespace api {

        interface ApiHandler {
            @doc("Retrieves zero or more events based on the provided request parameters.")
            GetLogEventsResult getLogEvents(GetLogEventsRequest request);
        }

        class GetLogEventsRequest extends Serializable {

            static GetLogEventsRequest decode(String encoded) {
                return ?Serializable.decodeClassName("mdk_tracing.api.GetLogEventsRequest", encoded);
            }

            @doc("""
                 Filter out all log events from the response that
                 occurred before this time. Milliseconds since UNIX
                 epoch. If this key is not set OR the value is null
                 then all events since the beginning of time will be
                 returned.
            """)
            long startTime = 0L;

            @doc("""
                 Filter out all log events from the response that
                 occurred after this time. Milliseconds since UNIX
                 epoch. If this key is not set OR the value is null
                 then all recorded events since the startTime will be
                 returned.
            """)
            long endTime = now();

            // TODO: concept of pagination and page size will likely be necessary before long.
            //@doc("Return the next page of results.")
            //String nextPageId;
            //int maximumResults;
        }

        class GetLogEventsResult extends Serializable {

            static GetLogEventsResult decode(String encoded) {
                return ?Serializable.decodeClassName("mdk_tracing.api.GetLogEventsResult", encoded);
            }

            @doc("The result of the query operation.")
            List<protocol.LogEvent> result;

            // TODO: concept of pagination size will likely be necessary before long.
            //@doc("Indicates the ID of the next page to return. If the ID is null then this is the last page.")
            //String nextPageId;
        }
    }

    namespace protocol {

        interface TracingHandler extends ProtocolHandler {
            void onLogEvent(LogEvent event);
        }

        @doc("""A single event in the stream that Tracing has to manage.""")
        class TracingEvent extends ProtocolEvent {

            static ProtocolEvent construct(String type) {
                ProtocolEvent result = ProtocolEvent.construct(type);
                if (result != null) { return result; }
                if (LogEvent._discriminator.matches(type)) { return new LogEvent(); }
                return null;
            }

            static ProtocolEvent decode(String encoded) {
                return ?Serializable.decodeClassName("mdk_tracing.protocol.LogEvent", encoded);
            }

            void dispatchTracingEvent(TracingHandler handler);

        }

        class LogEvent extends TracingEvent {

            static Discriminator _discriminator = anyof(["log"]);

            @doc("""Shared context""")
            SharedContext context;

            @doc("""
                 The timestamp When did this happen? This is stored as
                 milliseconds since the Unix epoch, and is filled in
                 by the client.
                 """)
            long timestamp;

            @doc("A string identifying the node from which this message originates.")
            String node;

            @doc("Log level")
            String level;

            @doc("Log category")
            String category;

            @doc("Describes the type of content contained in the text field. This is a mime type.")
            String contentType;

            @doc("The content of the log message.")
            String text;

            void dispatch(ProtocolHandler handler) {
                dispatchTracingEvent(?handler);
            }

            void dispatchTracingEvent(TracingHandler handler) {
                handler.onLogEvent(self);
            }

            String toString() {
                return "<LogEvent @" + timestamp.toString() + " " + context.toString() +
                    ", " + node + ", " + level + ", " + category + ", " + contentType + ", " + text + ">";
            }

        }

        class TracingClient extends WSClient {

            Tracer _tracer;
            bool _started = false;
            Lock _mutex = new Lock();

            List<LogEvent> _buffered = [];
            long _logged = 0L;
            long _sent = 0L;

            TracingClient(Tracer tracer) {
                _tracer = tracer;
            }

            String url() {
                return _tracer.url;
            }

            String token() {
                return _tracer.token;
            }

            bool isStarted() {
                _mutex.acquire();
                int size = _buffered.size();
                _mutex.release();
                return _started || size > 0;
            }

            void stop() {
                _started = false;
                super.stop();
            }

            void pump() {
                _mutex.acquire();
                while (_buffered.size() > 0) {
                    LogEvent evt = _buffered.remove(0);
                    self.sock.send(evt.encode());
                    _sent = _sent + 1;
                }
                _mutex.release();
            }

            void log(LogEvent evt) {
                _logged = _logged + 1;
                _mutex.acquire();
                _buffered.add(evt);
                if (!_started) {
                    self.start();
                    _started = true;
                }
                _mutex.release();
            }

        }

    }
}
