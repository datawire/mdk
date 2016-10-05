quark 1.0;

include protocol-1.0.q;
include util-1.0.q;

import mdk_runtime.actors;
import mdk_protocol;
import mdk_util;

namespace mdk_discovery {
    namespace protocol {

        @doc("""
        Create a Discovery service client using standard MDK env variables and
        register it with the MDK.
        """)
        class DiscoClientFactory extends DiscoverySourceFactory {
            WSClient wsclient;

            DiscoClientFactory(WSClient wsclient) {
                self.wsclient = wsclient;
            }

            DiscoverySource create(Actor subscriber, MDKRuntime runtime) {
                return new DiscoClient(subscriber, wsclient, runtime);
            }

            bool isRegistrar() {
                return true;
            }
        }

        @doc("""
        A source of discovery information that talks to Datawire Discovery server.

        Also supports registering discovery information with the server.
        """)
        class DiscoClient extends DiscoHandler, DiscoverySource, DiscoveryRegistrar {
            FailurePolicyFactory _failurePolicyFactory;
            MessageDispatcher _dispatcher;
            Time _timeService;
            Actor _subscriber;  // We will send discovery events here
            WSClient _wsclient; // The WSClient we will use
            // Clusters we advertise to the disco service.
            Map<String, Cluster> registered = new Map<String, Cluster>();

            Logger dlog = new Logger("discovery");

            long lastHeartbeat = 0L;
            Actor sock; // Websocket actor for the WS connection

            DiscoClient(Actor disco_subscriber, WSClient wsclient, MDKRuntime runtime) {
                self._subscriber = disco_subscriber;
                self._wsclient = wsclient;
                self._wsclient.subscribe(self);
                self._failurePolicyFactory = ?runtime.dependencies.getService("failurepolicy_factory");
                self._timeService = runtime.getTimeService();
            }

            void onStart(MessageDispatcher dispatcher) {
                self._dispatcher = dispatcher;
            }

            void onStop() {}

            void onMessage(Actor origin, Object message) {
                String klass = message.getClass().id;
                // Someone wants to register a node with discovery server:
                if (klass == "mdk_discovery.RegisterNode") {
                    RegisterNode register = ?message;
                    _register(register.node);
                    return;
                }
                // WSClient has connected to the server:
                if (klass == "mdk_protocol.WSConnected") {
                    WSConnected connected = ?message;
                    self.sock = connected.websock;
                    heartbeat();
                }
                // The WSClient is telling us we can send periodic messages:
                if (klass == "mdk_protocol.Pump") {
                    long rightNow = (self._timeService.time()*1000.0).round();
                    long heartbeatInterval = (self._wsclient.ttl/2.0*1000.0).round();
                    if (rightNow - self.lastHeartbeat >= heartbeatInterval) {
                        self.lastHeartbeat = rightNow;
                        heartbeat();
                    }
                    return;
                }
                // The WSClient has received a message:
                if (klass == "mdk_runtime.WSMessage") {
                    WSMessage wsmessage = ?message;
                    onWSMessage(wsmessage.body);
                    return;
                }
            }

            @doc("Register a node with the remote Discovery server.")
            void _register(Node node) {
                String service = node.service;
                if (!registered.contains(service)) {
                    registered[service] = new Cluster(self._failurePolicyFactory);
                }
                registered[service].add(node);

                // Trigger send of delta if we are connected, otherwise do
                // nothing because the full set of nodes will be resent
                // when we connect/reconnect.
                if (self._wsclient.isConnected()) {
                    active(node);
                }
            }

            void active(Node node) {
                Active active = new Active();
                active.node = node;
                active.ttl = self._wsclient.ttl;
                self._dispatcher.tell(self, active.encode(), self.sock);
                dlog.info("active " + node.toString());
            }

            void expire(Node node) {
                Expire expire = new Expire();
                expire.node = node;
                self._dispatcher.tell(self, expire.encode(), self.sock);
                dlog.info("expire " + node.toString());
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
                self._dispatcher.tell(self, new NodeActive(active.node), self._subscriber);
            }

            void onExpire(Expire expire) {
                // Remove the node from our available set.
                self._dispatcher.tell(self, new NodeExpired(expire.node), self._subscriber);
            }

            void onClear(Clear reset) {
                // ???
            }

            @doc("Send all registered services.")
            void heartbeat() {
                List<String> services = self.registered.keys();
                int idx = 0;
                while (idx < services.size()) {
                    int jdx = 0;
                    List<Node> nodes = self.registered[services[idx]].nodes;
                    while (jdx < nodes.size()) {
                        active(nodes[jdx]);
                        jdx = jdx + 1;
                    }
                    idx = idx + 1;
                }
            }

            void shutdown() {
                List<String> services = self.registered.keys();
                int idx = 0;
                while (idx < services.size()) {
                    int jdx = 0;
                    List<Node> nodes = self.registered[services[idx]].nodes;
                    while (jdx < nodes.size()) {
                        expire(nodes[jdx]);
                        jdx = jdx + 1;
                    }
                    idx = idx + 1;
                }
            }

            void onWSMessage(String message) {
                // Decode and dispatch incoming messages.
                ProtocolEvent event = DiscoveryEvent.decode(message);
                if (event == null) {
                    // Unknown message, drop it on the floor. The decoding will
                    // already have logged it.
                    return;
                }

                event.dispatch(self);
            }

        }

        interface DiscoHandler extends ProtocolHandler {
            void onActive(Active active);
            void onExpire(Expire expire);
            void onClear(Clear reset);
        }

        class DiscoveryEvent extends ProtocolEvent {

            static ProtocolEvent construct(String type) {
                ProtocolEvent result = ProtocolEvent.construct(type);
                if (result != null) { return result; }
                if (Active._discriminator.matches(type)) { return new Active(); }
                if (Expire._discriminator.matches(type)) { return new Expire(); }
                if (Clear._discriminator.matches(type)) { return new Clear(); }
                return null;
            }

            static ProtocolEvent decode(String message) {
                return ?Serializable.decodeClassName("mdk_discovery.protocol.DiscoveryEvent", message);
            }

            void dispatch(ProtocolHandler handler) {
                dispatchDiscoveryEvent(?handler);
            }

            void dispatchDiscoveryEvent(DiscoHandler handler);
        }

        /*@doc("""
          Advertise a node as being active. This can be used to register a
          new node or to heartbeat an existing node. The receiver must
          consider the node to be available for the duration of the
          specified ttl.
          """)*/
        class Active extends DiscoveryEvent {

            static Discriminator _discriminator = anyof(["active", "discovery.protocol.Active"]);

            @doc("The advertised node.")
            Node node;
            @doc("The ttl of the node in seconds.")
            float ttl;

            void dispatchDiscoveryEvent(DiscoHandler handler) {
                handler.onActive(self);
            }

        }

        @doc("Expire a node.")
        class Expire extends DiscoveryEvent {

            static Discriminator _discriminator = anyof(["expire", "discovery.protocol.Expire"]);

            Node node;

            void dispatchDiscoveryEvent(DiscoHandler handler) {
                handler.onExpire(self);
            }
        }

        @doc("Expire all nodes.")
        class Clear extends DiscoveryEvent {

            static Discriminator _discriminator = anyof(["clear", "discovery.protocol.Clear"]);

            void dispatchDiscoveryEvent(DiscoHandler handler) {
                handler.onClear(self);
            }
        }
    }
}
