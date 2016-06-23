quark 1.0;

use datawire_common.q;

import quark.concurrent;
import protocol;

namespace discovery {
    namespace protocol {

        @doc("The protocol machinery that wires together the public disco API to a server.")
        class DiscoClient extends DiscoHandler, HTTPHandler, WSHandler, Task {

            static Logger log = new Logger("discovery");

            Discovery disco;
            float firstDelay = 1.0;
            float maxDelay = 16.0;
            float reconnectDelay = firstDelay;
            float ttl = 30.0;

            WebSocket sock = null;
            bool authenticating = false;
            long lastHeartbeat = 0L;

            DiscoClient(Discovery discovery) {
                disco = discovery;
            }

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

            void register(Node node) {
                // Trigger send of delta if we are connected, otherwise do
                // nothing because the full set of nodes will be resent
                // when we connect/reconnect.

                if (isConnected()) {
                    active(node);
                }
            }

            void active(Node node) {
                Active active = new Active();
                active.node = node;
                active.ttl = ttl;
                sock.send(active.encode());
                log.info("active " + node.toString());
            }

            void resolve(Node node) {
                // Right now the disco protocol will notify about any
                // node, so we don't need to do anything here, if we
                // wanted to change this, we'd have to track the set of
                // nodes we are interested in resolving and communicate as
                // this changes.
            }

            void onOpen(Open open) {
                // Should assert version here ...
            }

            void onActive(Active active) {
                // Stick the node in the available set.

                Node node = active.node;
                node.finish(null);

                disco.active(node);
            }

            void onExpire(Expire expire) {
                // Remove the node from our available set.

                // hmm, we could make all Node objects we hand out be
                // continually updated until they expire...

                Node node = expire.node;

                disco.expire(node);
            }

            void onClear(Clear reset) {
                // ???
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
          
          
                  - Disco.started holds the desired connectedness
                  state. The isConnected() accessor holds the actual
                  connectedness state. If these differ then do what is
                  necessry to make the desired state actual.
          
                  - If we haven't sent a heartbeat recently enough, then
                  do that.
                */

                if (isConnected()) {
                    if (disco.started) {
                        long interval = ((ttl/2.0)*1000.0).round();
                        long rightNow = now();

                        if (rightNow - lastHeartbeat >= interval) {
                            heartbeat();
                        }
                    }
                    else {
                        sock.close();
                        sock = null;
                    }
                }
                else {
                    open(disco.url);
                }
            }

            void open(String url) {
                if (disco.token != null) {
                    url = url + "/?token=" + disco.token;
                }

                log.info("opening " + url);

                Context.runtime().open(url, self);
            }

            void heartbeat() {
                List<String> services = disco.registered.keys();

                int idx = 0;

                while (idx < services.size()) {
                    int jdx = 0;

                    List<Node> nodes = disco.registered[services[idx]].nodes;

                    while (jdx < nodes.size()) {
                        active(nodes[jdx]);
                        jdx = jdx + 1;
                    }

                    idx = idx + 1;
                }

                lastHeartbeat = now();
                schedule(ttl/2.0);
            }

            void onWSInit(WebSocket socket) {/* unused */ }

            void onWSConnected(WebSocket socket) {
                // Whenever we (re)connect, notify the server of any
                // nodes we have registered.
                log.info("connected to " + disco.url);

                reconnectDelay = firstDelay;
                sock = socket;

                sock.send(new Open().encode());

                heartbeat();
            }

            void onWSMessage(WebSocket socket, String message) {
                // Decode and dispatch incoming messages.
                DiscoveryEvent event = DiscoveryEvent.decode(message);
                // disco.mutex.acquire();
                event.dispatch(self);
                // disco.mutex.release();
            }

            void onWSBinary(WebSocket socket, Buffer message) { /* unused */ }

            void onWSClosed(WebSocket socket) { /* unused */ }

            void onWSError(WebSocket socket, WSError error) {
                log.error(error.toString());
                // Any non-transient errors should be reported back to the
                // user via any Nodes they have requested.
            }

            void onWSFinal(WebSocket socket) {
                log.info("closed " + disco.url);
                sock = null;
                disco.mutex.acquire();

                if (disco.started) {
                    scheduleReconnect();
                }

                disco.mutex.release();
            }
        }

        interface DiscoHandler extends ProtocolHandler {
            void onOpen(Open open);
            void onActive(Active active);
            void onExpire(Expire expire);
            void onClear(Clear reset);
            void onClose(Close close);
        }

        class DiscoveryEvent extends ProtocolEvent {
            static DiscoveryEvent decode(String message) {
                return ?Serializable.decode(message);
            }
            void dispatch(DiscoHandler handler);
        }

        /*@doc("""
          Advertise a node as being active. This can be used to register a
          new node or to heartbeat an existing node. The receiver must
          consider the node to be available for the duration of the
          specified ttl.
          """)*/
        class Active extends DiscoveryEvent {
            @doc("The advertised node.")
            Node node;
            @doc("The ttl of the node in seconds.")
            float ttl;

            void dispatch(DiscoHandler handler) {
                handler.onActive(self);
            }
        }

        @doc("Expire a node.")
        class Expire extends DiscoveryEvent {
            Node node;

            void dispatch(DiscoHandler handler) {
                handler.onExpire(self);
            }
        }

        @doc("Expire all nodes.")
        class Clear extends DiscoveryEvent {
            void dispatch(DiscoHandler handler) {
                handler.onClear(self);
            }
        }
    }
}
