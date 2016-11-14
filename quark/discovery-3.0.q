quark 1.0;

package datawire_mdk_discovery 2.0.33;

include discovery-protocol-3.0.q;
include synapse.q;
include util-1.0.q;
include mdk_runtime.q;

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
        @doc("The name of the service.")
        String cluster;
        @doc("The Environment for all nodes in this message.")
        OperationalEnvironment environment = new OperationalEnvironment();

        ReplaceCluster(String cluster, OperationalEnvironment environment, List<Node> nodes) {
            self.nodes = nodes;
            self.cluster = cluster;
            self.environment = environment;
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

    @doc("Discovery actor for hard-coded static routes.")
    class _StaticRoutesActor extends DiscoverySource {
        Actor _subscriber;
        List<Node> _knownNodes;

        _StaticRoutesActor(Actor subscriber, List<Node> knownNodes) {
            self._subscriber = subscriber;
            self._knownNodes = knownNodes;
        }

        void onStart(MessageDispatcher dispatcher) {
            int idx = 0;
            while (idx < self._knownNodes.size()) {
                dispatcher.tell(self, new NodeActive(self._knownNodes[idx]),
                                self._subscriber);
                idx = idx + 1;
            }
        }

        void onMessage(Actor origin, Object message) {}
        void onStop() {}
    }

    @doc("Create a DiscoverySource with hard-coded static routes.")
    class StaticRoutes extends DiscoverySourceFactory {
        List<Node> _knownNodes;

        static StaticRoutes parseJSON(String json_encoded) {
            List<Node> nodes = [];
            fromJSON(Class.get("quark.List<mdk_discovery.Node>"), nodes,
                     json_encoded.parseJSON());
            return new StaticRoutes(nodes);
        }

        StaticRoutes(List<Node> knownNodes) {
            self._knownNodes = knownNodes;
        }

        bool isRegistrar() {
            return false;
        }

        DiscoverySource create(Actor subscriber, MDKRuntime runtime) {
            return new _StaticRoutesActor(subscriber, self._knownNodes);
        }
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
        Logger _log = new Logger("mdk.breaker");

        int _threshold;
        float _delay;
        Time _time;

        Lock _mutex = new Lock();
        bool _failed = false;
        int _failures = 0;
        float _lastFailure = 0.0;


        CircuitBreaker(Time time, int threshold, float retestDelay) {
            _threshold = threshold;
            _delay = retestDelay;
            _time = time;
        }

        void success() {
            _mutex.acquire();
            _failed = false;
            _failures = 0;
            _lastFailure = 0.0;
            _mutex.release();
        }

        void failure() {
            _mutex.acquire();
            _failures = _failures + 1;
            _lastFailure = _time.time();
            if (_threshold != 0 && _failures >= _threshold) {
                _log.info("BREAKER TRIPPED.");
                _failed = true;
            }
            _mutex.release();
        }

        bool available() {
            if (_failed) {
                _mutex.acquire();
                bool result = _time.time() - _lastFailure > _delay;
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
        Time time;

        CircuitBreakerFactory(MDKRuntime runtime) {
            self.time = runtime.getTimeService();
        }

        FailurePolicy create() {
            return new CircuitBreaker(time, threshold, retestDelay);
        }
    }

    @doc("FailurePolicy that records failures and successes.")
    class RecordingFailurePolicy extends FailurePolicy {
        int successes = 0;
        int failures = 0;

        void success() {
            self.successes = self.successes + 1;
        }

        void failure() {
            self.failures = self.failures + 1;
        }

        bool available() {
            return true;
        }
    }

    @doc("Factory for FailurePolicy useful for testing.")
    class RecordingFailurePolicyFactory extends FailurePolicyFactory {
        RecordingFailurePolicyFactory() {}

        FailurePolicy create() {
            return new RecordingFailurePolicy();
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
        // Versions that have been registered at some point in the past:
        List<String> _registeredVersions = [];

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
            Node result = new Node();
            result.address = node.address;
            result.version = node.version;
            result.service = node.service;
            result.properties = node.properties;
            result._policy = self.failurePolicy(node);
            return result;
        }

        @doc("Get the FailurePolicy for a Node.")
        FailurePolicy failurePolicy(Node node) {
            return self._failurepolicies[node.address];
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

        @doc("""
        Return whether node with semantically matching version was registered at
        some point.
        """)
        bool matchingVersionRegistered(String version) {
            int idx = 0;
            while (idx < _registeredVersions.size()) {
                if (versionMatch(version, _registeredVersions[idx])) {
                    return true;
                }
                idx = idx + 1;
            }
            return false;
        }

        @doc("Add a Node to the cluster (or, if it's already present in the cluster,")
        @doc("update its properties).  At present, this involves a linear search, so")
        @doc("very large Clusters are unlikely to perform well.")
        void add(Node node) {
            // Register the node's version if we haven't seen it before:
            int kdx = 0;
            bool foundVersion = false;
            while (kdx < _registeredVersions.size()) {
                if (_registeredVersions[kdx] == node.version) {
                    foundVersion = true;
                    break;
                }
                kdx = kdx + 1;
            }
            if (!foundVersion) {
                _registeredVersions.add(node.version);
            }

            // Create FailurePolicy for new addresses:
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
                        // It's possible the factory's promise was already
                        // resolved if we're dealing with fallback environments,
                        // in which case a factory might be added to two
                        // Clusters. See Discovery.resolve() implementation.
                        if (!req.factory.promise.value().hasValue()) {
                            req.factory.resolve(self._copyNode(node));
                        }
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
        @doc("The Environment the Node is in.")
        OperationalEnvironment environment = new OperationalEnvironment();

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
        Logger logger = new Logger("discovery");

        // Clusters the disco says are available, as well as clusters for
        // which we are awaiting resolution.
        // Maps environment -> (servicename -> Cluster).
        Map<String, Map<String, Cluster>> services = {};

        bool started = false;
        Lock mutex = new Lock();
        MDKRuntime runtime;
        FailurePolicyFactory _fpfactory;
        UnaryCallable _notificationCallback = null;

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

        @doc("Get the service to Cluster mapping for an Environment.")
        Map<String,Cluster> _getServices(OperationalEnvironment environment) {
            if (!services.contains(environment.name)) {
                services[environment.name] = {};
            }
            return services[environment.name];
        }

        @doc("Get the Cluster for a given service and environment.")
        Cluster _getCluster(String service, OperationalEnvironment environment) {
            Map<String,Cluster> clusters = _getServices(environment);
            if (!clusters.contains(service)) {
                clusters[service] = new Cluster(self._fpfactory);
            }
            return clusters[service];
        }

        @doc("""
        Return the current known Nodes for a service in a particular
        Environment, if any.
        """)
        List<Node> knownNodes(String service, OperationalEnvironment environment) {
            return _getCluster(service, environment).nodes;
        }

        @doc("Get the FailurePolicy for a Node.")
        FailurePolicy failurePolicy(Node node) {
            return _getCluster(node.service, node.environment).failurePolicy(node);
        }

        @doc("Resolve a service name into an available service node. You must")
        @doc("usually start the uplink before this will do much; see start().")
        @doc("The returned Promise will end up with a Node as its value.")
        Promise resolve(String service, String version, OperationalEnvironment environment) {
            PromiseResolver factory = new PromiseResolver(runtime.dispatcher);

            self._lock();
            Cluster cluster = _getCluster(service, environment);
            if (!cluster.matchingVersionRegistered(version)) {
                // We've never seen a Node registered with a matching version. So
                // check if there is parent environment, and if so use it.
                OperationalEnvironment fallback = environment.getFallback();
                if (fallback != null) {
                    Cluster fallbackCluster = _getCluster(service, fallback);
                    if (!fallbackCluster.matchingVersionRegistered(version)) {
                        // Neither main nor fallback cluster know about this
                        // service, so we want to get whichever gets an answer
                        // first.  Register with fallback cluster here, we'll
                        // register with main cluster below:
                        fallbackCluster._addRequest(version, factory);
                    } else {
                        self._release();
                        // Fallback cluster knows about this service, so lets use
                        // it:
                        return resolve(service, version, fallback);
                    }
                }
            }

            Node result = cluster.chooseVersion(version);
            if (result == null) {
                cluster._addRequest(version, factory);
                self._release();
            } else {
                self._release();
                factory.resolve(result);
            }

            return factory.promise;
        }

        void onMessage(Actor origin, Object message) {
            if (_notificationCallback != null) {
                _notificationCallback.__call__(message);
            }
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
                self._replace(replace.cluster, replace.environment, replace.nodes);
                return;
            }
        }

        void _replace(String service, OperationalEnvironment environment,
                      List<Node> nodes) {
            self._lock();
            logger.info("replacing all nodes for " + service + " with "
                        + nodes.toString());
            Cluster cluster = _getCluster(service, environment);
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
            logger.info("adding " + node.toString());

            Cluster cluster = _getCluster(node.service, node.environment);
            cluster.add(node);

            self._release();
        }

        // XXX PRIVATE API -- needs to not be here.
        // @doc("Expire a given node.")
        void _expire(Node node) {
            self._lock();
            logger.info("removing " + node.toString() + " from cluster");

            _getCluster(node.service, node.environment).remove(node);
            // We don't check remove clusters with no nodes because they might
            // have unresolved promises in _waiting.

            self._release();
        }

        @doc("Register a callable that will be called with all incoming messages.")
        void notify(UnaryCallable callback) {
            self._notificationCallback = callback;
        }
    }

}
