quark 1.0;

use protocol.q;

import protocol;

namespace discovery {
    namespace protocol {

        @doc("The protocol machinery that wires together the public disco API to a server.")
        class DiscoClient extends WSClient, DiscoHandler {

            static Logger dlog = new Logger("discovery");

            Discovery disco;

            DiscoClient(Discovery discovery) {
                disco = discovery;
            }

            String url() {
                return disco.url;
            }

            String token() {
                return disco.token;
            }

            bool isStarted() {
                return disco.started;
            }

            void register(Node node) {
                // Trigger send of delta if we are connected, otherwise do
                // nothing because the full set of nodes will be resent
                // when we connect/reconnect.

                if (self.isConnected()) {
                    active(node);
                }
            }

            void active(Node node) {
                Active active = new Active();
                active.node = node;
                active.ttl = self.ttl;
                self.sock.send(active.encode());
                dlog.info("active " + node.toString());
            }

            void resolve(Node node) {
                // Right now the disco protocol will notify about any
                // node, so we don't need to do anything here, if we
                // wanted to change this, we'd have to track the set of
                // nodes we are interested in resolving and communicate as
                // this changes.
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
            }

            void onWSMessage(WebSocket socket, String message) {
                // Decode and dispatch incoming messages.
                DiscoveryEvent event = DiscoveryEvent.decode(message);
                // disco.mutex.acquire();
                event.dispatch(self);
                // disco.mutex.release();
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
