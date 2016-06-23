quark 1.0;

package datawire_protocol 1.0.0;

import quark.reflect;

namespace protocol {

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
             Every SharedContext is given an ID at the moment of its
             creation; this is its originId. Every operation started
             as a result of the thing that caused the SharedContext to
             be created must use the same SharedContext, and its
             originId will _never_ _change_.
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

    interface ProtocolHandler {
        void onOpen(Open open);
        void onClose(Close close);
    }

    class ProtocolEvent extends Serializable {
        static ProtocolEvent decode(String message) {
            return ?Serializable.decode(message);
        }
    }

    class Open extends ProtocolEvent {

        String version = "2.0.0";

        void dispatch(ProtocolHandler handler) {
            handler.onOpen(self);
        }
    }

    // XXX: this should probably go somewhere in the library
    @doc("A value class for sending error informationto a remote peer.")
    class ProtocolError {
        @doc("Symbolic error code, alphanumerics and underscores only.")
        String code;

        @doc("Human readable short description.")
        String title;

        @doc("A detailed description.")
        String detail;

        @doc("A unique identifier for this particular occurrence of the problem.")
        String id;
    }

    @doc("Close the event stream.")
    class Close extends ProtocolEvent {
        ProtocolError error;

        void dispatch(ProtocolHandler handler) {
            handler.onClose(self);
        }
    }

}
