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
            String token;

            DiscoClientFactory(String token) {
                self.token = token;
            }

            DiscoverySource create(Actor subscriber, MDKRuntime runtime) {
                EnvironmentVariable ddu = runtime.getEnvVarsService().var("MDK_DISCOVERY_URL");
                String url = ddu.orElseGet("wss://discovery.datawire.io/ws/v1");
                return new DiscoClient(subscriber, token, url, runtime);
            }

            bool isRegistrar() {
                return true;
            }
        }

        @doc("""
        A source of discovery information that talks to Datawire Discovery server.

        Also supports registering discovery information with the server.
        """)
        class DiscoClient extends WSClient, DiscoHandler, DiscoverySource, DiscoveryRegistrar {
            bool _started = false;
            String _token;
            String _url;
            FailurePolicyFactory _failurePolicyFactory;
            MessageDispatcher _dispatcher;
            Actor _subscriber;  // We will send discovery events here

            // Clusters we advertise to the disco service.
            Map<String, Cluster> registered = new Map<String, Cluster>();

            Logger dlog = new Logger("discovery");

            DiscoClient(Actor subscriber, String token, String url, MDKRuntime runtime) {
                super(runtime);
                self._subscriber = subscriber;
                self._failurePolicyFactory = ?runtime.dependencies.getService("failurepolicy_factory");
                self._token = token;
                self._url = url;
            }

            // Actor interface; placeholder for when we stop using WSClient as
            // a superclass.
            void onStart(MessageDispatcher dispatcher) {
                self._dispatcher = dispatcher;
                self._started = true;
                super.onStart(dispatcher);
            }

            void onStop() {
                self._started = false;
                super.onStop();
            }

            void onMessage(Actor origin, Object message) {
                if (message.getClass().id == "mdk_discovery.RegisterNode") {
                    RegisterNode register = ?message;
                    _register(register.node);
                    return;
                }
                super.onMessage(origin, message);
            }

            String url() {
                return self._url;
            }

            String token() {
                return self._token;
            }

            bool isStarted() {
                return self._started;
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
                if (self.isConnected()) {
                    active(node);
                }
            }

            void active(Node node) {
                Active active = new Active();
                active.node = node;
                active.ttl = self.ttl;
                self.dispatcher.tell(self, active.encode(), self.sock);
                dlog.info("active " + node.toString());
            }

            void expire(Node node) {
                Expire expire = new Expire();
                expire.node = node;
                self.dispatcher.tell(self, expire.encode(), self.sock);
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

            void startup() {
                heartbeat();
            }

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
