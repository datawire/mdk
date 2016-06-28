quark 1.0;

package datawire_tracing 1.0.0;

use protocol.q;
use datawire_introspection.q;

import quark.concurrent;
import mdk.protocol;
import datawire_introspection;

import tracing.protocol;

@doc("""
Tracing is the log collector for the MDK.

A brief event overview:

- RequestStart and RequestEnd are meant to bracket the whole request, which
  will almost certainly comprise multiple records, so that:
  - we needn’t repeat the args and such all the time, and
  - it's a bit easier to do whole-request analysis later.
- LogRecord carries log messages. Again, there will likely be many of these
  for a given request.

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

namespace tracing {

    class SharedContextInitializer extends TLSInitializer<SharedContext> {
        SharedContext getValue() {
            return new SharedContext();
        }
    }

    class Tracer {
        static Logger logger = new Logger("MDK Tracer");

        String host = "philadelphia-test.datawire.io";
        String url = "wss://" + host + "/ws";
        String token = DatawireToken.getToken();

        TLS<SharedContext> _context = new TLS<SharedContext>(new SharedContextInitializer());
        protocol.TracingClient _client;

        Tracer() {
            _client = new protocol.TracingClient(self);
        }

        void setContext(SharedContext context) {
            _context.setValue(context);
        }

        SharedContext getContext() {
            return _context.getValue();
        }

        void startRequest(String url) {
            RequestStart start = new RequestStart();
            start.url = url;
            logRecord(start);
        }

        void endRequest() {
            RequestEnd end = new RequestEnd();
            logRecord(end);
        }

        void log(String level, String category, String text) {
            LogMessage msg = new LogMessage();
            msg.level = level;
            msg.category = category;
            msg.text = text;
            logRecord(msg);
        }

        void logRecord(LogRecord record) {
            LogEvent evt = new LogEvent();
            evt.context = getContext();
            evt.timestamp = now();
            evt.record = record;
            _client.log(evt);
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

            String url = "https://" + self.host + "/api/logs";

            if (args.size() > 0) {
                url = url + "?" + "&".join(args);
            }

            // Off we go.
            HTTPRequest req = new HTTPRequest(url);

            req.setMethod("GET");
            req.setHeader("Content-Type", "application/json");
            req.setHeader("Authorization", "Bearer " + self.token);

            logger.info("curl -H 'Content-Type: application/json' \\");
            logger.info("     -H 'Authorization: Bearer " + self.token + "' \\");
            logger.info("     '" + url + "'");

            return IO.httpRequest(req).andThen(bind(self, "handleQueryResponse", []));
        }

        Object handleQueryResponse(HTTPResponse response) {
            int code = response.getCode();      // HTTP status code
            String body = response.getBody();   // just to save keystrokes later

            logger.info("query got: " + code.toString());
            logger.info("body: " + body);

            if (code == 200) {
                // All good. Parse the JSON in the body...
                logger.info("All good!");
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
                return ?Serializable.decodeClassName("tracing.api.GetLogEventsRequest", encoded);
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
                return ?Serializable.decodeClassName("tracing.api.GetLogEventsResult", encoded);
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
                return ?Serializable.decodeClassName("tracing.protocol.LogEvent", encoded);
            }

            void dispatchTracingEvent(TracingHandler handler);

        }

        class LogEvent extends TracingEvent {

            static Discriminator _discriminator = anyof(["log"]);

            @doc("""Shared context""")
            SharedContext context;
            @doc("""
                 When did this happen? This is stored as milliseconds
                 since the Unix epoch, and is filled in by the client.
            """)
            long timestamp;
            LogRecord record;

            void dispatch(ProtocolHandler handler) {
                dispatchTracingEvent(?handler);
            }

            void dispatchTracingEvent(TracingHandler handler) {
                handler.onLogEvent(self);
            }
        }

        interface RecordHandler {
            void onRequestStart(RequestStart start);
            void onLogMessage(LogMessage msg);
            void onRequestEnd(RequestEnd end);
        }

        @doc("""A event that contains information solely about tracing.""")
        class LogRecord {

            @doc("The node at which we're tracing this record.")
            String node;

            void dispatch(RecordHandler handler);
        }

        @doc("""
             Log an event for later viewing. This is the most common event.
        """)
        class LogMessage extends LogRecord {
            @doc("Log category")
            String category;
            @doc("Log level")
            String level;
            @doc("The actual log message")
            String text;

            void dispatch(RecordHandler handler) {
                handler.onLogMessage(self);
            }

            // XXX Not automagically mapped to str() or the like, even though
            // something should be.
            String toString() {
                return "<LogMessage " + self.node.toString() + " (" + self.category + " " + self.level + ": " + self.text + ">";
            }
        }

        @doc("""
             Note that a request is starting. This is the only place
             the parameters to the request appear, and it's also the
             event that assigns the reqctx for this request.
        """)
        class RequestStart extends LogRecord {
            String url;
            @doc("Parameters of the new request, if any.")
            Map<String, String> params;
            @doc("Headers of the new request, if any.")
            List<String> headers;

            void dispatch(RecordHandler handler) {
                handler.onRequestStart(self);
            }

            // XXX Not automagically mapped to str() or the like, even though
            // something should be.
            String toString() {
                return "<ReqStart " + self.node.toString() + ">";
            }
        }

        @doc("Note that a request has ended.")
        class RequestEnd extends LogRecord {

            void dispatch(RecordHandler handler) {
                handler.onRequestEnd(self);
            }

            // XXX Not automagically mapped to str() or the like, even though
            // something should be.
            String toString() {
                return "<ReqEnd " + self.node.toString() + ">";
            }
        }

        class TracingClient extends WSClient {

            Tracer _tracer;
            bool _started = false;
            Lock _mutex = new Lock();

            List<LogEvent> _buffered = [];

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
                return true;
            }

            void heartbeat() {
                _mutex.acquire();
                while (_buffered.size() > 0) {
                    LogEvent evt = _buffered.remove(0);
                    self.sock.send(evt.encode());
                }
                _mutex.release();
            }

            void log(LogEvent evt) {
                _mutex.acquire();
                if (!_started) {
                    self.start();
                    _started = true;
                }
                _buffered.add(evt);
                _mutex.release();
                if (self.isConnected()) {
                    self.heartbeat();
                }
            }

        }

    }
}
