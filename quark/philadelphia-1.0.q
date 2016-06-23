quark 1.0;

use mdk-1.0.q;

import discovery;

namespace mdk {
  class Serializable {
    static Serializable decode(String message) {
      JSONObject json = message.parseJSON();
      String type = json["type"];
      Class clazz = Class.get(type);
      Serializable obj = ?clazz.construct([]);
      fromJSON(clazz, obj, json);

      return obj;
    }

    String encode() {
      Class clazz = self.getClass();
      JSONObject json = toJSON(self, clazz);
      json["type"] = clazz.getName();
      return json.toString();
    }
  }

  class SharedContext extends Serializable {
    @doc("""
      Every SharedContext is given an ID at the moment of its creation;
      this is its originId. Every operation started as a result of the
      thing that caused the SharedContext to be created must use the 
      same SharedContext, and its originId will _never_ _change_.
    """)
    String originId;
    @doc("""
      To track causality, we use a Lamport clock, which we track as a
      list of integers.
    """)
    List<int> clocks;
    @doc("""
      We also provide a map of properties for later extension. Rememeber
      that these, too, will be shared across the whole system.
    """)
    Map<String, Object> properties;

    // XXX ew.
    static SharedContext decode(String message) {
      return ?Serializable.decode(message);
    }

    // XXX Not automagically mapped to str() or the like, even though
    // something should be.
    String toString() {
      return "<SharedContext " + self.originId + ">";
    }
  }
}

@doc("""
Philadelphia is the log collector for the MDK.

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

namespace philadelphia {

  namespace api {

    interface ApiHandler {
      @doc("Retrieves zero or more events based on the provided request parameters.")
      GetLoggingEventsResponse getLoggingEvents(GetLoggingEventsRequest request);
    }

    class GetLoggingEventsRequest {
      @doc("""Filter out all logging events from the response that occurred before this time. Milliseconds since UNIX
      epoch. If this key is not set OR the value is null then all events since the beginning of time will be returned.
      """)
      long startTime = 0L;

      @doc("""Filter out all logging events from the response that occurred after this time. Milliseconds since UNIX
      epoch. If this key is not set OR the value is null then all recorded events since the startTime will be
      returned.
      """)
      long endTime = now();

      // TODO: concept of pagination and page size will likely be necessary before long.
      //@doc("Return the next page of results.")
      //String nextPageId;
      //int maximumResults;
    }

    class GetLoggingEventsResponse {
      @doc("The result of the query operation.")
      List<protocol.LoggingEvent> result;

      // TODO: concept of pagination size will likely be necessary before long.
      //@doc("Indicates the ID of the next page to return. If the ID is null then this is the last page.")
      //String nextPageId;
    }

  }

  namespace protocol {
    interface PhiladelphiaHandler {
      void onReqStart(RequestStart event);
      void onReqEnd(RequestEnd event);
      void onLogMessage(LogMessage event);
    }

    @doc("""A event that contains information solely about logging.""")
    class LogRecord extends mdk.Serializable {
      @doc("The node at which we're logging this record.")
      Node node;

      // XXX ew.
      static LogRecord decode(String message) {
        return ?mdk.Serializable.decode(message);
      }
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

      // // XXX ew.
      // static LogMessage decode(String message) {
      //   return ?mdk.Serializable.decode(message);
      // }

      void dispatch(PhiladelphiaHandler handler) {
        handler.onLogMessage(self);
      }

      // XXX Not automagically mapped to str() or the like, even though
      // something should be.
      String toString() {
        return "<LogMessage " + self.node.toString() + " (" + self.category + " " + self.level + ": " + self.text + ">";
      }
    }

    @doc("""
    Note that a request is starting. This is the only place the parameters
    to the request appear, and it's also the event that assigns the reqctx
    for this request.
    """)
    class RequestStart extends LogRecord {
      @doc("Parameters of the new request, if any.")
      Map<String, String> params;
      @doc("Headers of the new request, if any.")
      List<String> headers;

      // // XXX ew.
      // static RequestStart decode(String message) {
      //   return ?mdk.Serializable.decode(message);
      // }

      void dispatch(PhiladelphiaHandler handler) {
        handler.onReqStart(self);
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

      // // XXX ew.
      // static RequestStart decode(String message) {
      //   return ?mdk.Serializable.decode(message);
      // }

      void dispatch(PhiladelphiaHandler handler) {
        handler.onReqEnd(self);
      }

      // XXX Not automagically mapped to str() or the like, even though
      // something should be.
      String toString() {
        return "<ReqEnd " + self.node.toString() + ">";
      }
    }

    @doc("""A single event in the stream that Philadelphia has to manage.""")
    // Note that we extend only DiscoveryEvent -- without multiple 
    // inheritance we can't extend Serializable too, but then
    // DiscoveryEvent encompasses encode and decode anyway.
    //
    // XXX This is probably going to bite me.

    class LoggingEvent extends discovery.protocol.DiscoveryEvent {
      @doc("""Shared context""")
      mdk.SharedContext context;
      @doc("""
        When did this happen? This is stored as milliseconds since the
        Unix epoch, and is filled in by the client.
      """)
      long timestamp;

      // // XXX ew.
      // static LoggingEvent decode(String message) {
      //   return ?mdk.Serializable.decode(message);
      // }

      void dispatch(PhiladelphiaHandler handler);
    }

    // XXX: this should probably go somewhere in the library
    @doc("A value class for sending error informationto a remote peer.")
    class Error {
      @doc("Symbolic error code, alphanumerics and underscores only.")
      String code;

      @doc("Human readable short description.")
      String title;

      @doc("A detailed description.")
      String detail;

      @doc("A unique identifier for this particular occurrence of the problem.")
      String id;
    }
  }
}
