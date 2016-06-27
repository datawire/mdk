quark 1.0;

package datawire_protocol 1.0.0;

import quark.concurrent;
import quark.reflect;

namespace mdk {
namespace protocol {

    class Serializable {

        static Serializable decodeClass(Class clazz, String encoded) {
            JSONObject json = encoded.parseJSON();
            String type = json["type"];
            Method meth = clazz.getMethod("construct");
            Serializable obj;
            if (meth != null) {
                obj = ?meth.invoke(null, [type]);
                if (obj == null) {
                    panic(clazz.getName() + "." + meth.getName() + " could not understand this json: " + encoded);
                }
                clazz = obj.getClass();
            } else {
                obj = ?clazz.construct([]);
                if (obj == null) {
                    panic("could not construct " + clazz.getName() + " from this json: " + encoded);
                }
            }

            fromJSON(clazz, obj, json);

            return obj;
        }

        static Serializable decodeClassName(String name, String encoded) {
            return decodeClass(Class.get(name), encoded);
        }

        String encode() {
            Class clazz = self.getClass();
            JSONObject json = toJSON(self, clazz);
            String type = ?self.getField("_descriminator");
            if (type != null) {
                json["type"] = type;
            }
            String encoded = json.toString();
            return encoded;
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

        // XXX this could work a lot nicer with a parameterized method
        // in Serialize and a static class reference
        static SharedContext decode(String encoded) {
            return ?Serializable.decodeClassName("mdk.protocol.SharedContext", encoded);
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
        static ProtocolEvent construct(String type) {
            if (type == Open._descriminator) { return new Open(); }
            if (type == Close._descriminator) { return new Close(); }
            return null;
        }
        void dispatch(ProtocolHandler handler);
    }

    class Open extends ProtocolEvent {

        static String _descriminator = "open";

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

        static String _descriminator = "close";

        ProtocolError error;

        void dispatch(ProtocolHandler handler) {
            handler.onClose(self);
        }
    }

    @doc("Common protocol machinery for web socket based protocol clients.")
    class WSClient extends ProtocolHandler, WSHandler, Task {

        static Logger logger = new Logger("protocol");

        float firstDelay = 1.0;
        float maxDelay = 16.0;
        float reconnectDelay = firstDelay;
        float ttl = 30.0;

        WebSocket sock = null;
        long lastHeartbeat = 0L;
        String sockUrl = null;

        String url();
        String token();
        bool isStarted();

        bool isConnected() {
            return sock != null;
        }

        void start() {
            schedule(0.0);
        }

        void stop() {
            schedule(0.0);
        }

        void schedule(float time) {
            Context.runtime().schedule(self, time);
        }

        void scheduleReconnect() {
            schedule(reconnectDelay);
            reconnectDelay = 2.0*reconnectDelay;

            if (reconnectDelay > maxDelay) {
                reconnectDelay = maxDelay;
            }
        }

        void onOpen(Open open) {
            // Should assert version here ...
        }

        void onClose(Close close) {
            logger.info("close: " + close.toString());
        }

        void onExecute(Runtime runtime) {
            /*
              Do our periodic chores here, this will involve checking
              the desired state held by disco against our actual
              state and taking any measures necessary to address the
              difference:
          
          
              - isStarted() holds the desired connectedness
              state. The isConnected() accessor holds the actual
              connectedness state. If these differ then do what is
              necessry to make the desired state actual.
          
              - If we haven't sent a heartbeat recently enough, then
              do that.
            */

            if (isConnected()) {
                if (isStarted()) {
                    long interval = ((ttl/2.0)*1000.0).round();
                    long rightNow = now();

                    if (rightNow - lastHeartbeat >= interval) {
                        doHeartbeat();
                    }
                } else {
                    sock.close();
                    sock = null;
                }
            } else {
                open(url());
            }
        }

        void open(String url) {
            String tok = token();
            if (tok != null) {
                url = url + "?token=" + tok;
            }

            logger.info("opening " + url);

            Context.runtime().open(url, self);
            sockUrl = url;
        }

        void heartbeat() {}
        
        void doHeartbeat() {
            heartbeat();
            lastHeartbeat = now();
            schedule(ttl/2.0);
        }

        void onWSInit(WebSocket socket) {/* unused */ }

        void onWSConnected(WebSocket socket) {
            // Whenever we (re)connect, notify the server of any
            // nodes we have registered.
            logger.info("connected to " + sockUrl);

            reconnectDelay = firstDelay;
            sock = socket;

            sock.send(new Open().encode());

            doHeartbeat();
        }

        void onWSBinary(WebSocket socket, Buffer message) { /* unused */ }

        void onWSClosed(WebSocket socket) { /* unused */ }

        void onWSError(WebSocket socket, WSError error) {
            logger.error(error.toString());
            // Any non-transient errors should be reported back to the
            // user via any Nodes they have requested.
        }

        void onWSFinal(WebSocket socket) {
            logger.info("closed " + sockUrl);
            sock = null;
            if (isStarted()) {
                scheduleReconnect();
            }
        }
    }

}}
