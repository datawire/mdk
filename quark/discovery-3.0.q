quark 1.0;

package datawire_mdk_discovery 3.5.0;

include discovery-protocol-3.0.q;
include synapse.q;
use util-1.0.q;
use mdk_runtime.q;

import quark.concurrent;
import quark.reflect;

import mdk_discovery.protocol;
import mdk_util;  // bring in EnvironmentVariable, WaitForPromise
import mdk_runtime;
import mdk_runtime.actors;
import mdk_runtime.promise;

/*
  Context:

  For phase one, all our user wants to do is have a convenient
  library to get an address to connect to that is backed by a
  realtime discovery service rather than DNS. The mechanism for
  connecting is entirely in the user's code, all we do is provide
  an address (likely in the form of a url, but really it's just an
  opaque string that was advertised by a service instance).

  Behind the scenes we will do client side load balancing and
  possibly fancier routing in the future, but the user doesn't
  observe this directly through the API. The user *does* observe
  this indirectly because they don't need to deploy a central load
  balancer.

  Conceptually, we should strive to be a drop-in replacement for
  dns, with the one difference being that the server process is
  creating the dns record directly rather than a system
  administrator.
*/

namespace mdk_discovery {

    @doc("Message from DiscoverySource: a node has become active.")
    class NodeActive {
        Node node;

        NodeActive(Node node) {
            self.node = node;
        }
    }

    @doc("Message from DiscoverySource: a node has expired.")
    class NodeExpired {
        Node node;

        NodeExpired(Node node) {
            self.node = node;
        }
    }

    @doc("Message from DiscoverySource: replace all nodes in a particular Cluster.")
    class ReplaceCluster {
        List<Node> nodes;
        String cluster;

        ReplaceCluster(String cluster, List<Node> nodes) {
            self.nodes = nodes;
            self.cluster = cluster;
        }
    }

    @doc("""
    A source of discovery information.

    Sends ReplaceCluster, NodeActive and NodeExpired messages to a
    subscriber.
    """)
    interface DiscoverySource extends Actor {}

    @doc("A factory for DiscoverySource instances.")
    interface DiscoverySourceFactory {
        @doc("Create a new instance")
        DiscoverySource create(Actor subscriber, MDKRuntime runtime);

        @doc("""
        If true, the returned DiscoverySource is also a DiscoveryRegistrar.
        """)
        bool isRegistrar();
    }

    @doc("Message sent to DiscoveryRegistrar Actor to register a node.")
    class RegisterNode {
        Node node;

        RegisterNode(Node node) {
            self.node = node;
        }
    }

    @doc("""
    Allow registration of services.

    Send this an actor a RegisterNode message to do so.
    """)
    interface DiscoveryRegistrar extends Actor {}


    class _Request {

        String version;
        PromiseResolver factory;

        _Request(String version, PromiseResolver factory) {
            self.version = version;
            self.factory = factory;
        }

    }

    @doc("A policy for choosing how to deal with failures.")
    interface FailurePolicy {
        @doc("Record a success for the Node this policy is managing.")
        void success();

        @doc("Record a failure for the Node this policy is managing.")
        void failure();

        @doc("Return whether the Node should be accessed.")
        bool available();

    }

    @doc("A factory for FailurePolicy.")
    class FailurePolicyFactory {
        @doc("Create a new FailurePolicy.")
        FailurePolicy create();
    }

    @doc("Default circuit breaker policy.")
    class CircuitBreaker extends FailurePolicy {
        static Logger _log = new Logger("mdk.breaker");

        int _threshold;
        long _delay;

        Lock _mutex = new Lock();
        bool _failed = false;
        int _failures = 0;
        long _lastFailure = 0L;


        CircuitBreaker(int threshold, float retestDelay) {
            _threshold = threshold;
            _delay = (retestDelay*1000.0).round();
        }

        void success() {
            _mutex.acquire();
            _failed = false;
            _failures = 0;
            _lastFailure = 0;
            _mutex.release();
        }

        void failure() {
            _mutex.acquire();
            _failures = _failures + 1;
            _lastFailure = now();
            if (_threshold != 0 && _failures >= _threshold) {
                _log.info("BREAKER TRIPPED.");
                _failed = true;
            }
            _mutex.release();
        }

        bool available() {
            if (_failed) {
                _mutex.acquire();
                bool result = now() - _lastFailure > _delay;
                _mutex.release();
                if (result) {
                    _log.info("BREAKER RETEST.");
                }
                return result;
            } else {
                return true;
            }
        }
    }

    @doc("Create CircuitBreaker instances.")
    class CircuitBreakerFactory extends FailurePolicyFactory {
        int threshold = 3;
        float retestDelay = 30.0;

        FailurePolicy create() {
            return new CircuitBreaker(threshold, retestDelay);
        }
    }

    @doc("A Cluster is a group of providers of (possibly different versions of)")
    @doc("a single service. Each service provider is represented by a Node.")
    class Cluster {
        List<Node> nodes = [];
        List<_Request> _waiting = [];
        Map<String,FailurePolicy> _failurepolicies = {}; // Maps address->FailurePolicy
        int _counter = 0;
        FailurePolicyFactory _fpfactory;

        Cluster(FailurePolicyFactory fpfactory) {
            self._fpfactory = fpfactory;
        }

        @doc("Choose a single Node to talk to. At present this is a simple round")
        @doc("robin.")
        Node choose() {
            return chooseVersion(null);
        }

        @doc("Create a Node for external use.")
        Node _copyNode(Node node) {
            FailurePolicy policy = self._failurepolicies[node.address];
            Node result = new Node();
            result.address = node.address;
            result.version = node.version;
            result.service = node.service;
            result.properties = node.properties;
            result._policy = policy;
            return result;
        }

        @doc("Choose a compatible version of a service to talk to.")
        Node chooseVersion(String version) {
            if (nodes.size() == 0) { return null; }

            int start = _counter % nodes.size();
            _counter = _counter + 1;
            int count = 0;
            while (count < nodes.size()) {
                int choice = (start + count) % nodes.size();
                Node candidate = nodes[choice];
                FailurePolicy policy = self._failurepolicies[candidate.address];
                if (versionMatch(version, candidate.version) && policy.available()) {
                    return self._copyNode(candidate);
                }
                count = count + 1;
            }

            return null;
        }

        @doc("Add a Node to the cluster (or, if it's already present in the cluster,")
        @doc("update its properties).  At present, this involves a linear search, so")
        @doc("very large Clusters are unlikely to perform well.")
        void add(Node node) {
            if (!_failurepolicies.contains(node.address)) {
                _failurepolicies[node.address] = self._fpfactory.create();
            }

            // Resolve waiting promises:
            if (self._waiting.size() > 0) {
                List<_Request> waiting = self._waiting;
                self._waiting = [];
                int jdx = 0;
                while (jdx < waiting.size()) {
                    _Request req = waiting[jdx];
                    if (versionMatch(req.version, node.version)) {
                        req.factory.resolve(self._copyNode(node));
                    } else {
                        self._waiting.add(req);
                    }
                    jdx = jdx + 1;
                }
            }

            // Update stored values:
            int idx = 0;
            while (idx < nodes.size()) {
                if (nodes[idx].address == node.address) {
                    nodes[idx] = node;
                    return;
                }
                idx = idx + 1;
            }
            nodes.add(node);
        }

        // Internal method, add PromiseResolver to fill in when a new Node is added.
        void _addRequest(String version, PromiseResolver factory) {
            _waiting.add(new _Request(version, factory));
        }

        @doc("Remove a Node from the cluster, if it's present. If it's not present, do")
        @doc("nothing. Note that it is possible to remove all the Nodes and be left with")
        @doc("an empty cluster.")
        void remove(Node node) {
            int idx = 0;

            while (idx < nodes.size()) {
                Node ep = nodes[idx];

                if (ep.address == null || ep.address == node.address) {
                    nodes.remove(idx);
                    return;
                }

                idx = idx + 1;
            }

            // XXX: should this be an error? as it is, we silently ignore it.
        }

        @doc("Returns true if and only if this Cluster contains no Nodes.")
        bool isEmpty() {
            return (nodes.size() <= 0);
        }

        // XXX: toString() is a disaster for large clusters.
        @doc("Return a string representation of the Cluster.")
        @doc("")
        @doc("WARNING: every Node is represented in the string. Large Clusters will")
        @doc("produce unusably large strings.")
        String toString() {
            String result = "Cluster(";

            int idx = 0;

            while (idx < nodes.size()) {
                if (idx > 0) {
                    result = result + ", ";
                }

                result = result + nodes[idx].toString();
                idx = idx + 1;
            }

            result = result + ")";
            return result;
        }
    }

    @doc("The Node class captures address and metadata information about a")
    @doc("server functioning as a service instance.")
    class Node {

        @doc("The service name.")
        String service;
        @doc("The service version (e.g. '1.2.3')")
        String version;
        @doc("The address at which clients can reach the server.")
        String address;
        @doc("Additional metadata associated with this service instance.")
        Map<String,Object> properties = {};

        FailurePolicy _policy = null;

        void success() {
            _policy.success();
        }

        void failure() {
            _policy.failure();
        }

        bool available() {
            return _policy.available();
        }

        @doc("Return a string representation of the Node.")
        String toString() {
            // XXX: this doesn't get mapped into __str__, etc in targets
            String result = "Node(";

            if (service == null) {
                result = result + "<unnamed>";
            }
            else {
                result = result + service;
            }

            result = result + ": ";

            if (address == null) {
                result = result + "<unlocated>";
            }
            else {
                result = result + address;
            }

            if (version != null) {
                result = result + ", " + version;
            }

            result = result + ")";

            if (properties != null) {
                result = result + " " + properties.toString();
            }

            return result;
        }
    }

    @doc("The Discovery class functions as a conduit to a source of discovery information.")
    @doc("Using it, a provider can register itself as providing a particular service")
    @doc("(see the register method) and a consumer can locate a provider for a")
    @doc("particular service (see the resolve method).")
    class Discovery extends Actor {
        static Logger logger = new Logger("discovery");

        // Clusters the disco says are available, as well as clusters for
        // which we are awaiting resolution.
        Map<String, Cluster> services = new Map<String, Cluster>();

        bool started = false;
        Lock mutex = new Lock();
        MDKRuntime runtime;
        FailurePolicyFactory _fpfactory;

        @doc("Construct a Discovery object. You must set the token before doing")
        @doc("anything else; see the withToken() method.")
        Discovery(MDKRuntime runtime) {
            logger.info("Discovery created!");
            self.runtime = runtime;
            self._fpfactory = ?runtime.dependencies.getService("failurepolicy_factory");
        }

        // XXX PRIVATE API.
        @doc("Lock.")
        void _lock() {
            mutex.acquire();
        }

        // XXX PRIVATE API.
        // @doc("Release the lock")
        void _release() {
            mutex.release();
        }

        @doc("Start the uplink to the discovery service.")
        void onStart(MessageDispatcher dispatcher) {
            self._lock();

            if (!started) {
                started = true;
            }

            self._release();
        }

        @doc("Stop the uplink to the discovery service.")
        void onStop() {
            self._lock();

            if (started) {
                started = false;
            }

            self._release();
        }

        @doc("Register info about a service node with a discovery source of truth. You must")
        @doc("usually start the uplink before this will do much; see start().")
        Discovery register(Node node) {
            DiscoveryRegistrar registrar;
            if (runtime.dependencies.hasService("discovery_registrar")) {
                registrar = ?runtime.dependencies.getService("discovery_registrar");
            } else {
                panic("Registration not supported as no Discovery Registrar was setup.");
            }
            self.runtime.dispatcher.tell(self, new RegisterNode(node), registrar);
            return self;
        }

        @doc("Register info about a service node with the discovery service. You must")
        @doc("usually start the uplink before this will do much; see start().")
        Discovery register_service(String service, String address, String version) {
            Node node = new Node();
            node.service = service;
            node.address = address;
            node.version = version;
            return self.register(node);
        }

        @doc("Return the current known Nodes for a service, if any.")
        List<Node> knownNodes(String service) {
            if (!services.contains(service)) {
                return [];
            }
            return services[service].nodes;
        }

        @doc("Resolve a service name into an available service node. You must")
        @doc("usually start the uplink before this will do much; see start().")
        @doc("The returned Promise will end up with a Node as its value.")
        Promise _resolve(String service, String version) {
            PromiseResolver factory = new PromiseResolver(runtime.dispatcher);

            self._lock();

            if (!services.contains(service)) {
                services[service] = new Cluster(self._fpfactory);
            }

            Node result = services[service].chooseVersion(version);
            if (result == null) {
                services[service]._addRequest(version, factory);
                self._release();
            } else {
                self._release();
                factory.resolve(result);
            }

            return factory.promise;
        }

        @doc("Resolve a service; return a (Bluebird) Promise on Javascript. Does not work elsewhere.")
        Object resolve(String service, String version) {
            return toNativePromise(_resolve(service, version));
        }

        // XXX blocking API, never call from Javascript or Quark code.
        @doc("Wait for service name to resolve into an available service node, or fail")
        @doc("appropriately (typically by raising an exception if the language")
        @doc("supports it). This should only be used in blocking runtimes (e.g. ")
        @doc("you do not want to use this in Javascript).")
        Node resolve_until(String service, String version, float timeout) {
            return ?WaitForPromise.wait(self._resolve(service, version), timeout, "service " + service);
        }

        void onMessage(Actor origin, Object message) {
            String klass = message.getClass().id;
            if (klass == "mdk_discovery.NodeActive") {
                NodeActive active = ?message;
                self._active(active.node);
                return;
            }
            if (klass == "mdk_discovery.NodeExpired") {
                NodeExpired expire = ?message;
                self._expire(expire.node);
                return;
            }
            if (klass == "mdk_discovery.ReplaceCluster") {
                ReplaceCluster replace = ?message;
                self._replace(replace.cluster, replace.nodes);
                return;
            }
        }

        void _replace(String service, List<Node> nodes) {
            self._lock();
            logger.info("replacing all nodes for " + service + " with "
                        + nodes.toString());
            if (!services.contains(service)) {
                services[service] = new Cluster(self._fpfactory);
            }
            Cluster cluster = services[service];
            List<Node> currentNodes = new ListUtil<Node>().slice(cluster.nodes,
                                                                 0,
                                                                 cluster.nodes.size());
            int idx = 0;
            while (idx < currentNodes.size()) {
                cluster.remove(currentNodes[idx]);
                idx = idx + 1;
            }
            idx = 0;
            while (idx < nodes.size()) {
                cluster.add(nodes[idx]);
                idx = idx + 1;
            }
            self._release();
        }

        // XXX PRIVATE API -- needs to not be here.
        // @doc("Add a given node.")
        void _active(Node node) {
            self._lock();

            String service = node.service;

            logger.info("adding " + node.toString());

            if (!services.contains(service)) {
                services[service] = new Cluster(self._fpfactory);
            }

            Cluster cluster = services[service];
            cluster.add(node);

            self._release();
        }

        // XXX PRIVATE API -- needs to not be here.
        // @doc("Expire a given node.")
        void _expire(Node node) {
            self._lock();

            String service = node.service;

            if (services.contains(service)) {
                Cluster cluster = services[service];

                logger.info("removing " + node.toString() + " from cluster");

                cluster.remove(node);
                // We don't check for or remove clusters with no nodes
                // because they might have unresolved promises in
                // _waiting.
            }

            self._release();
        }
    }
    
}
