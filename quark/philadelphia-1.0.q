quark 1.0;

use mdk-1.0.q;

import discovery;

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
      long startTime = 0;

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
      List<Object> result;

      // TODO: concept of pagination size will likely be necessary before long.
      //@doc("Indicates the ID of the next page to return. If the ID is null then this is the last page.")
      //String nextPageId;
    }

  }

  namespace protocol {
    interface PhiladelphiaHandler {
      void onReqStart(RequestStart event);
      void onReqEnd(RequestEnd event);
      void onLogRecord(LogRecord event);
    }

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

    @doc("""
      PhiladelphiaRequestContext identifies the context for a particular
      request. The context is created once, when the request first enters
      the mesh of services using Philadelphia for logging, and must be
      passed to every subsequent service.

      At present, the request context contains only a UUID. This will
      likely change.
    """)

    class PhiladelphiaRequestContext extends Serializable {
      @doc("The ID of this request")
      String id;

      // XXX ew.
      static PhiladelphiaRequestContext decode(String message) {
        return ?Serializable.decode(message);
      }

      // XXX Not automagically mapped to str() or the like, even though
      // something should be.
      String toString() {
        return "<reqctx " + self.id + ">";
      }
    }

    @doc("""A single event in the stream that Philadelphia has to manage.""")
    class PhiladelphiaEvent extends Serializable {
      String version;
      String messageType;
      String orgID;
      PhiladelphiaRequestContext reqctx;
      float timestamp;

      // XXX ew.
      static PhiladelphiaEvent decode(String message) {
        return ?Serializable.decode(message);
      }

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

    @doc("""
    Note that a request is starting. This is the only place the parameters
    to the request appear, and it's also the event that assigns the reqctx
    for this request.
    """)
    class RequestStart extends PhiladelphiaEvent {
      @doc("""
      The node at which we're first logging this request. Usually this will
      be the first node handling the request.
      """)
      Node node;
      @doc("Parameters of the new request, if any.")
      Map<String, String> params;
      @doc("Headers of the new request, if any.")
      List<String> headers;

      // XXX ew.
      static RequestStart decode(String message) {
        return ?Serializable.decode(message);
      }

      void dispatch(PhiladelphiaHandler handler) {
        handler.onReqStart(self);
      }

      // XXX Not automagically mapped to str() or the like, even though
      // something should be.
      String toString() {
        return "<ReqStart " + self.reqctx.id + ">";
      }
    }

    @doc("Note that a request has ended.")
    class RequestEnd extends PhiladelphiaEvent {
      @doc("An error if failure, or null for success.")
      Error error;

      // XXX ew.
      static RequestStart decode(String message) {
        return ?Serializable.decode(message);
      }

      void dispatch(PhiladelphiaHandler handler) {
        handler.onReqEnd(self);
      }

      // XXX Not automagically mapped to str() or the like, even though
      // something should be.
      String toString() {
        return "<ReqEnd " + self.reqctx.id + ">";
      }
    }

    @doc("""
    Log an event for later viewing. This is the most common event.
    """)
    class LogRecord extends PhiladelphiaEvent {
      @doc("The node at which we're logging this record.")
      Node node;
      @doc("Log category")
      String category;
      @doc("Log level")
      String level;
      @doc("The actual log message")
      String text;

      // XXX ew.
      static LogRecord decode(String message) {
        return ?Serializable.decode(message);
      }

      void dispatch(PhiladelphiaHandler handler) {
        handler.onLogRecord(self);
      }

      // XXX Not automagically mapped to str() or the like, even though
      // something should be.
      String toString() {
        return "<LogRecord " + self.reqctx.id + " (" + self.category + " " + self.level + ": " + self.text + ">";
      }
    }
  }
}
