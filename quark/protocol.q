quark 1.0;

package datawire_protocol 1.0.0;

import quark.concurrent;
import quark.reflect;

namespace mdk {
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
            // ???
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
                url = url + "/?token=" + tok;
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
