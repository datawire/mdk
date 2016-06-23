quark 1.0;

package datawire_tracing 1.0.0;

use datawire_common.q;

import protocol;

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

    namespace api {

        interface ApiHandler {
            @doc("Retrieves zero or more events based on the provided request parameters.")
            GetLogEventsResult getLogEvents(GetLogEventsRequest request);
        }

        class GetLogEventsRequest {
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

        class GetLogEventsResult {
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
        class LogEvent extends ProtocolEvent {
            @doc("""Shared context""")
            SharedContext context;
            @doc("""
                 When did this happen? This is stored as milliseconds
                 since the Unix epoch, and is filled in by the client.
            """)
            long timestamp;
            LogRecord record;

            // XXX ew.
            static LogEvent decode(String message) {
                return ?Serializable.decode(message);
            }

            void dispatch(TracingHandler handler);
        }

        interface RecordHandler {
            void onRequestStart(RequestStart start);
            void onLogMessage(LogMessage msg);
            void onRequestEnd(RequestEnd end);
        }

        @doc("""A event that contains information solely about tracing.""")
        class LogRecord extends Serializable {
            @doc("The node at which we're tracing this record.")
            String node;

            // XXX ew.
            static LogRecord decode(String message) {
                return ?Serializable.decode(message);
            }

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
            @doc("An error if failure, or null for success.")
            Error error;

            void dispatch(RecordHandler handler) {
                handler.onRequestEnd(self);
            }

            // XXX Not automagically mapped to str() or the like, even though
            // something should be.
            String toString() {
                return "<ReqEnd " + self.node.toString() + ">";
            }
        }

    }
}
