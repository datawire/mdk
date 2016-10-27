quark 1.0;

package datawire_mdk_tracing 2.0.26;

include protocol-1.0.q;
include introspection-1.0.q;
include rtp.q;

import mdk_runtime.actors;
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

    @doc("MDK can use this to handle logging on the Session.")
    interface TracingDestination extends Actor {
        @doc("Send a log message to the server.")
        void log(SharedContext ctx, String procUUID, String level,
                 String category, String text);
    }

    @doc("In-memory testing of logs.")
    class FakeTracer extends TracingDestination {
        List<Map<String,String>> messages = [];

        void log(SharedContext ctx, String procUUID, String level,
                 String category, String text) {
            messages.add({"level": level, "category": category,
                          "text": text, "context": ctx.traceId});
        }

        void onStart(MessageDispatcher dispatcher) {}
        void onStop() {}
        void onMessage(Actor origin, Object message) {}
    }

    @doc("Send log messages to the MCP server.")
    class Tracer extends Actor, TracingDestination {
        Logger logger = new Logger("MDK Tracer");
        long lastPoll = 0L;

        protocol.TracingClient _client;
        MDKRuntime runtime;

        Tracer(MDKRuntime runtime, WSClient wsclient) {
            self.runtime = runtime;
            self._client = new protocol.TracingClient(self, wsclient);
        }

        @doc("Backwards compatibility.")
        static Tracer withURLsAndToken(String url, String queryURL, String token) {
            return withURLAndToken(url, token);
        }

        static Tracer withURLAndToken(String url, String token) {
            MDKRuntime runtime = defaultRuntime();
            WSClient wsclient = new WSClient(runtime, mdk_rtp.getRTPParser(), url, token);
            runtime.dispatcher.startActor(wsclient);
            Tracer newTracer = new Tracer(runtime, wsclient);
            runtime.dispatcher.startActor(newTracer);
            return newTracer;
        }

        void onStart(MessageDispatcher dispatcher) {
            dispatcher.startActor(_client);
        }

        void onStop() {
            runtime.dispatcher.stopActor(_client);
        }

        void onMessage(Actor origin, Object mesage) {}

        @doc("Send a log message to the server.")
        void log(SharedContext ctx, String procUUID, String level,
                 String category, String text) {
            ctx.tick();
            logger.trace("CTX " + ctx.toString());

            LogEvent evt = new LogEvent();

            // Copy context so multiple events don't have the same
            // context object, which is getting mutated over time,
            // e.g., the ctx.tick() call above. This potentially
            // duplicates a large amount of baggage (ctx.properties),
            // but hopefully that baggage is empty/unused right now.
            // Perhaps a better workaround would be to send just the
            // relevant data from the context object. An actual
            // solution would involve having sensible definitions/APIs
            // for the context object and its clock.

            evt.context = ctx.copy();
            evt.timestamp = now();
            evt.node = procUUID;
            evt.level = level;
            evt.category = category;
            evt.contentType = "text/plain";
            evt.text = text;
            _client.log(evt);
        }

        void subscribe(UnaryCallable handler) {
            _client.subscribe(handler);
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

        class LogEvent extends Serializable, AckablePayload {
            static String _json_type = "log";

            @doc("""Shared context""")
            SharedContext context;

            @doc("""
                 The timestamp When did this happen? This is stored as
                 milliseconds since the Unix epoch, and is filled in
                 by the client.
                 """)
            long timestamp;

            long getTimestamp() {
                return self.timestamp;
            }

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

            String toString() {
                return "<LogEvent " + timestamp.toString() + " " + context.toString() +
                    ", " + node + ", " + level + ", " + category + ", " + contentType + ", " + text + ">";
            }

        }

        class Subscribe extends Serializable {
            static String _json_type = "subscribe";

            String toString() {
                return "<Subscribe>";
            }
        }

        class LogAck extends Serializable {
            static String _json_type = "logack";

            @doc("Sequence number of the last log message being acknowledged.")
            long sequence;

            String toString() {
                return "<LogAck " + sequence.toString() + ">";
            }

        }

        class TracingClient extends WSClientSubscriber {

            Tracer _tracer;
            bool _started = false;
            Lock _mutex = new Lock();
            UnaryCallable _handler = null;
            MessageDispatcher _dispatcher;

            WSClient _wsclient; // The WSClient we will use
            Actor _sock = null; // The websocket we're connected to, if any
            SendWithAcks _sendWithAcks;

            TracingClient(Tracer tracer, WSClient wsclient) {
                _tracer = tracer;
                _wsclient = wsclient;
                _sendWithAcks = new SendWithAcks();
                wsclient.subscribe(self);
            }

            @doc("Attach a subscriber that will receive results of queries.")
            void subscribe(UnaryCallable handler) {
                _mutex.acquire();
                _handler = handler;
                _mutex.release();
            }

            void onStart(MessageDispatcher dispatcher) {
                self._dispatcher = dispatcher;
            }

            void onStop() {}

            void onMessage(Actor origin, Object message) {
                _subscriberDispatch(self, message);
            }

            void onWSConnected(Actor websock) {
                _mutex.acquire();
                self._sock = websock;
                self._sendWithAcks.onConnected(self, self._dispatcher, websock);
                if (_handler != null) {
                    self._dispatcher.tell(self, new Subscribe().encode(), self._sock);
                }
                _mutex.release();
            }

            void onPump() {
                _mutex.acquire();
                self._sendWithAcks.onPump(self, self._dispatcher, self._sock);
                _mutex.release();
            }

            void onMessageFromServer(Object message) {
                String type = message.getClass().id;
                if (type == "mdk_tracing.protocol.LogEvent") {
                    LogEvent event = ?message;
                    onLogEvent(event);
                    return;
                }
                if (type == "mdk_tracing.protocol.LogAck") {
                    LogAck ack = ?message;
                    self.onLogAck(ack);
                    return;
                }
            }

            void onLogEvent(LogEvent evt) {
                _mutex.acquire();
                if (_handler != null) {
                    _handler.__call__(evt);
                }
                _mutex.release();
            }

            void onLogAck(LogAck ack) {
                _mutex.acquire();
                self._sendWithAcks.onAck(ack.sequence);
                _mutex.release();
            }

            @doc("Queue a log message for delivery to the server.")
            void log(LogEvent evt) {
                _mutex.acquire();
                self._sendWithAcks.send(evt._json_type, evt);
                _mutex.release();
            }

        }

    }
}
