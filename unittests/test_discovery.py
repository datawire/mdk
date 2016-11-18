"""
Tests for Discovery.
"""

from __future__ import absolute_import
from builtins import range
from builtins import object

from unittest import TestCase
from json import dumps
from uuid import uuid4

from hypothesis.stateful import GenericStateMachine
from hypothesis import strategies as st

from .common import fake_runtime, SANDBOX_ENV, create_node, MDKConnector

from mdk_discovery import (
    Discovery, NodeActive, NodeExpired, ReplaceCluster,
    CircuitBreakerFactory, StaticRoutes, Node,
)
from mdk_discovery.protocol import Active
from mdk import _parseEnvironment


def create_disco():
    """
    Create a new Discovery instance.
    """
    runtime = fake_runtime()
    disco = Discovery(runtime)
    disco.onStart(runtime.dispatcher)
    return disco


def resolve(disco, service, version, environment="sandbox"):
    """Resolve a service to a Node."""
    return disco.resolve(service, version,
                         _parseEnvironment(environment)).value().getValue()


def knownNodes(disco, service, environment="sandbox"):
    """Return known nodes for a service."""
    return disco.knownNodes(service, _parseEnvironment(environment))


class NodeTests(TestCase):
    """Tests for Node."""
    def test_id(self):
        """Node.getId() uses Node.id if present."""
        node = Node()
        node.id = "1234"
        self.assertEqual(node.getId(), node.id)

    def test_missingId(self):
        """Node.getId() uses the datawire_nodeId property if the id is not set."""
        node = Node()
        node.properties["datawire_nodeId"] = "4567"
        self.assertEqual(node.getId(), "4567")


class DiscoveryTests(TestCase):
    """Tests for Discovery."""

    def assertNodesEqual(self, a, b):
        """The two Nodes have the same values."""
        self.assertEqual((a.version, a.address, a.service, a.properties),
                         (b.version, b.address, b.service, b.properties))

    def test_active(self):
        """NodeActive adds a Node to Discovery."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        self.assertEqual(knownNodes(disco, "myservice", "sandbox"), [node])

    def test_resolve(self):
        """resolve() returns a Node matching an active one."""
        disco = create_disco()
        node = create_node("somewhere")
        node.properties = {"x": 1}
        disco.onMessage(None, NodeActive(node))
        resolved = resolve(disco, "myservice", "1.0")
        self.assertEqual(
            (resolved.version, resolved.address, resolved.service, resolved.properties),
            ("1.0", "somewhere", "myservice", {"x": 1}))

    def test_activeUpdatesMatchingAddress(self):
        """NodeActive updates a Node with same address to new version and properties."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        node2 = create_node("somewhere")
        node2.version = "1.7"
        node2.properties = {"a": 123}
        disco.onMessage(None, NodeActive(node2))
        self.assertEqual(knownNodes(disco, "myservice", "sandbox"), [node2])
        resolved = resolve(disco, "myservice", "1.7")
        self.assertEqual((resolved.version, resolved.properties),
                         ("1.7", {"a": 123}))

    def test_activeUpdatesMatchingId(self):
        """NodeActive updates a Node with same id as existing one."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        node2 = create_node("somewhere_else")
        node2.id = node.id
        node2.version = "1.7"
        node2.properties = {"a": 123}
        disco.onMessage(None, NodeActive(node2))
        self.assertEqual(knownNodes(disco, "myservice", "sandbox"), [node2])
        resolved = resolve(disco, "myservice", "1.7")
        self.assertEqual((resolved.version, resolved.properties),
                         ("1.7", {"a": 123}))

    def test_activeTriggersWaitingPromises(self):
        """
        NodeActive causes waiting resolve() Promises to get a Node.
        """
        disco = create_disco()
        result = []
        promise = disco.resolve("myservice", "1.0",
                                SANDBOX_ENV)
        promise.andThen(result.append)
        self.assertFalse(result)

        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        self.assertNodesEqual(result[0], node)

    def test_expired(self):
        """NodeExpired removes a Node from Discovery."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        disco.onMessage(None, NodeExpired(node))
        self.assertEqual(knownNodes(disco, "myservice", "sandbox"), [])

    def test_expiredUnknown(self):
        """NodeExpired does nothing for unknown Node."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeExpired(node))
        self.assertEqual(knownNodes(disco, "myservice", "sandbox"), [])

    def test_replace(self):
        """
        ReplaceCluster replaces the contents of a Cluster (collection of Nodes for
        the same service name).
        """
        disco = create_disco()
        node1 = create_node("somewhere")
        node2 = create_node("somewhere2")
        node3 = create_node("somewhere3")
        node4 = create_node("somewhere4")
        disco.onMessage(None, NodeActive(node1))
        disco.onMessage(None, NodeActive(node2))
        disco.onMessage(None, ReplaceCluster("myservice",
                                             SANDBOX_ENV,
                                             [node3, node4]))
        self.assertEqual(knownNodes(disco, "myservice", "sandbox"), [node3, node4])

    def test_replaceEmpty(self):
        """
        ReplaceCluster register nodes when the Discovery source is empty.
        """
        disco = create_disco()
        node1 = create_node("somewhere")
        node2 = create_node("somewhere2")
        disco.onMessage(None, ReplaceCluster("myservice",
                                             SANDBOX_ENV,
                                             [node1, node2]))
        self.assertEqual(knownNodes(disco, "myservice", "sandbox"), [node1, node2])

    def test_replaceTriggersWaitingPromises(self):
        """
        ReplaceCluster causes waiting resolve() Promises to get a Node.
        """
        disco = create_disco()
        result = []
        promise = disco.resolve("myservice", "1.0",
                                SANDBOX_ENV)
        promise.andThen(result.append)
        self.assertFalse(result)

        node = create_node("somewhere")
        disco.onMessage(None, ReplaceCluster("myservice",
                                             SANDBOX_ENV,
                                             [node]))
        self.assertNodesEqual(result[0], node)

    def test_activeDoesNotMutate(self):
        """
        A resolved Node is not mutated by a new NodeActive for same address.
        """
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = resolve(disco, "myservice", "1.0")

        node2 = create_node("somewhere")
        node2.version = "1.3"
        disco.onMessage(None, NodeActive(node2))
        self.assertEqual(resolved_node.version, "1.0")

    def test_replaceDoesNotMutate(self):
        """
        A resolved Node is not mutated by a new ReplaceCluster containing a Node
        with the same address.
        """
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = resolve(disco, "myservice", "1.0")

        node2 = create_node("somewhere")
        node2.version = "1.3"
        disco.onMessage(None, ReplaceCluster("myservice",
                                             SANDBOX_ENV,
                                             [node2]))
        self.assertEqual(resolved_node.version, "1.0")

    def test_nodeCircuitBreaker(self):
        """success()/failure() enable and disable the Node."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = resolve(disco, "myservice", "1.0")

        avail1 = resolved_node.available()
        # Default threshold in CircuitBreaker is three failures:
        resolved_node.failure()
        resolved_node.failure()
        resolved_node.failure()
        avail2 = resolved_node.available()
        resolved_node.success()
        avail3 = resolved_node.available()
        self.assertEqual((avail1, avail2, avail3), (True, False, True))

    def test_activeDoesNotDisableCircuitBreaker(self):
        """
        If a Node has been disabled by a CircuitBreaker then NodeActive with same
        Node doesn't re-enable it.
        """
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = resolve(disco, "myservice", "1.0")
        # Uh-oh it's a pretty broken node:
        for i in range(10):
            resolved_node.failure()

        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node2 = resolve(disco, "myservice", "1.0")
        self.assertEqual(resolved_node2, None)
        resolved_node.success()
        self.assertNodesEqual(resolve(disco, "myservice", "1.0"), node)

    def test_replaceDoesNotDisableCircuitBreaker(self):
        """
        If a Node has been disabled by a CircuitBreaker then ReplaceCluster with
        same Node doesn't re-enable it.
        """
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = resolve(disco, "myservice", "1.0")
        # Uh-oh it's a pretty broken node:
        for i in range(10):
            resolved_node.failure()

        node = create_node("somewhere")
        disco.onMessage(None, ReplaceCluster("myservice",
                                             SANDBOX_ENV,
                                             [node]))
        resolved_node2 = resolve(disco, "myservice", "1.0")
        self.assertEqual(resolved_node2, None)
        resolved_node.success()
        self.assertNodesEqual(resolve(disco, "myservice", "1.0"), node)

    def test_notify(self):
        """
        The notify() API allows getting all events passed to the Discovery instance.
        """
        disco = create_disco()
        messages = [object(), NodeActive(create_node("hello"))]
        result = []
        disco.notify(result.append)
        for m in messages:
            disco.onMessage(None, m)
        self.assertEqual(messages, result)


class DiscoveryEnvironmentTests(TestCase):
    """Tests for interaction between Discovery and environments."""

    def test_activeIsEnvironmentSpecific(self):
        """ActiveNode only updates the Environment set on the Node."""
        node = create_node("somewhere", "myservice", "env1")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        self.assertEqual((knownNodes(disco, "myservice", "env1"),
                          knownNodes(disco, "myservice", "env2")),
                         ([node], []))

    def test_expireIsEnvironmentSpecific(self):
        """ExpireNode only updates the Environment set on the Node."""
        node = create_node("somewhere", "myservice", "env1")
        node2 = create_node("somewhere2", "myservice", "env2")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        disco.onMessage(None, NodeActive(node2))
        disco.onMessage(None, NodeExpired(node))
        self.assertEqual((knownNodes(disco, "myservice", "env1"),
                          knownNodes(disco, "myservice", "env2")),
                         ([], [node2]))

    def test_replaceIsEnvironmentSpecific(self):
        """ReplaceCluster only updates the Environment set on the Node."""
        node = create_node("somewhere", "myservice", "env1")
        node2 = create_node("somewhere2", "myservice", "env2")
        node3 = create_node("somewhere3", "myservice", "env2")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        disco.onMessage(None, NodeActive(node2))
        disco.onMessage(None, ReplaceCluster(node3.service, node3.environment,
                                             [node3]))
        self.assertEqual((knownNodes(disco, "myservice", "env1"),
                          knownNodes(disco, "myservice", "env2")),
                         ([node], [node3]))

    def test_resolve(self):
        """Resolve is limited to the specified environment."""
        node = create_node("somewhere", "myservice", "env1")
        node2 = create_node("somewhere2", "myservice", "env2")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        disco.onMessage(None, NodeActive(node2))
        # Do repeatedly in case round robin is somehow tricking us:
        for i in range(10):
            self.assertEqual(resolve(disco, "myservice", "1.0", "env1").address,
                             "somewhere")
        for i in range(10):
            self.assertEqual(resolve(disco, "myservice", "1.0", "env2").address,
                             "somewhere2")

    def test_environmentInheritance(self):
        """
        If an Environment has a parent it is checked if there have never been Nodes
        with that service name registered in the child Environment.
        """
        # In the parent only
        node = create_node("somewhere", "myservice", "parent")
        # In the child
        node2 = create_node("somewhere2", "myservice2", "parent:child")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        disco.onMessage(None, NodeActive(node2))
        # Do repeatedly in case round robin is somehow tricking us:
        for i in range(10):
            self.assertEqual(resolve(disco, "myservice", "1.0", "parent:child").address,
                             "somewhere")
        for i in range(10):
            self.assertEqual(resolve(disco, "myservice2", "1.0", "parent:child").address,
                             "somewhere2")

    def test_environmentInheritanceVersions(self):
        """
        If an Environment has a parent it is checked if there are no Nodes that have
        ever been registered with that service and version in the child
        Environment.
        """
        # This one won't work if we need 1.0:
        node = create_node("somewhere2.0", "myservice", "parent:child")
        node.version = "2.0"
        # So we expect to fall back to this:
        node2 = create_node("somewhere1.0", "myservice", "parent")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        disco.onMessage(None, NodeActive(node2))
        # Do repeatedly in case round robin is somehow tricking us:
        for i in range(10):
            self.assertEqual(resolve(disco, "myservice", "1.0", "parent:child").address,
                             "somewhere1.0")

    def test_environmentReverseInheritance(self):
        """
        A parent environment doesn't get access to Nodes in the child environment.
        """
        # In the child only
        node = create_node("somewhere", "myservice", "parent:child")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        # Parent can't find it
        self.assertEqual(resolve(disco, "myservice", "1.0", "parent"), None)

    def test_noInheritanceAfterRegister(self):
        """
        Once a service/version pair have been registered in the child environment,
        the parent environment isn't used even if there are currently no nodes
        available in the child.
        """
        node = create_node("somewhere", "myservice", "parent:child")
        disco = create_disco()
        disco.onMessage(None, NodeActive(node))
        # Uh oh, service went away in the child!
        disco.onMessage(None, NodeExpired(node))
        # But it still exists in parent
        node2 = create_node("somewhere2", "myservice", "parent")
        disco.onMessage(None, NodeActive(node2))
        # However, since it existed in the child before, we won't get version
        # from the parent.
        self.assertEqual(resolve(disco, "myservice", "1.0", "parent:child"),
                         None)

    def test_unknownServiceChildArrivesFirst(self):
        """
        If resolution can't return an answer immediately, and the child environment
        gets a node later on, the resolution gets that result.
        """
        env = _parseEnvironment("parent:child")
        node = create_node("somewhere", "myservice", "parent:child")
        disco = create_disco()
        promise = disco.resolve("myservice", "1.0", env)
        disco.onMessage(None, NodeActive(node))
        self.assertEqual(promise.value().getValue().address, "somewhere")
        # If a parent node arrives we don't blow up:
        disco.onMessage(None, NodeActive(create_node("somewhereelse", "myservice",
                                                     "parent")))

    def test_unknownServiceParentArrivesFirst(self):
        """
        If resolution can't return an answer immediately, and the parent environment
        gets a node later on, the resolution gets that result.
        """
        env = _parseEnvironment("parent:child")
        node = create_node("somewhere", "myservice", "parent")
        disco = create_disco()
        promise = disco.resolve("myservice", "1.0", env)
        disco.onMessage(None, NodeActive(node))
        self.assertEqual(promise.value().getValue().address, "somewhere")
        # If a child node arrives we don't blow up:
        disco.onMessage(None, NodeActive(create_node("somewhereelse", "myservice",
                                                     "parent:child")))


class CircuitBreakerTests(TestCase):
    """
    Tests for CircuitBreaker.
    """
    def setUp(self):
        runtime = fake_runtime()
        self.time = runtime.getTimeService()
        self.circuit_breaker = CircuitBreakerFactory(runtime).create();

    def test_noFailure(self):
        """If not failures occur the node is available."""
        for i in range(10):
            self.assertTrue(self.circuit_breaker.available())

    def test_break(self):
        """If threshold number of failures happen the node becomes unavailable."""
        self.circuit_breaker.failure()
        available1 = self.circuit_breaker.available()
        self.circuit_breaker.failure()
        available2 = self.circuit_breaker.available()
        self.circuit_breaker.failure()
        available3 = self.circuit_breaker.available()
        available4 = self.circuit_breaker.available()
        self.assertEqual((available1, available2, available3, available4),
                         (True, True, False, False))

    def test_timeoutReset(self):
        """After enough time has passed the CircuitBreaker resets to available."""
        for i in range(3):
            self.circuit_breaker.failure()
        self.time.advance(29.0)
        available29sec = self.circuit_breaker.available()
        self.time.advance(1.1)
        available30sec = self.circuit_breaker.available()
        self.assertEqual((available29sec, available30sec),
                         (False, True))

    def test_successReset(self):
        """
        A successful connection resets the threshold for a Node becoming
        unavailable.
        """
        for i in range(3):
            self.circuit_breaker.failure()
        self.circuit_breaker.success()
        available0 = self.circuit_breaker.available()
        self.circuit_breaker.failure()
        available1 = self.circuit_breaker.available()
        self.circuit_breaker.failure()
        available2 = self.circuit_breaker.available()
        self.circuit_breaker.failure()
        available3 = self.circuit_breaker.available()
        available4 = self.circuit_breaker.available()
        self.assertEqual((available0, available1, available2, available3, available4),
                         (True, True, True, False, False))

class FakeDiscovery(object):
    """Parallel, simplified Discovery state tracking implementation."""

    def __init__(self):
        self.services = {}

    def is_empty(self):
        return all([not addresses for addresses in list(self.services.values())])

    def add(self, service, address):
        self.services.setdefault(service, set()).add(address)

    def remove(self, service, address):
        if service in self.services:
            addresses = self.services[service]
            if address in addresses:
                addresses.remove(address)

    def replace(self, service, addresses):
        self.services[service] = set(addresses)

    def compare(self, real_discovery):
        """Compare us to a real Discovery instance, assert same state."""
        real_services = {}
        for name, cluster in list(real_discovery.services["sandbox"].items()):
            real_services[name] = set(node.address for node in cluster.nodes)
        assert self.services == real_services


nice_strings = st.text(alphabet="abcdefghijklmnop", min_size=1, max_size=10)
# Add a random node:
add_strategy = st.tuples(st.just("add"),
                         st.tuples(nice_strings, nice_strings))
# Replace a random service:
replace_strategy = st.tuples(st.just("replace"),
                             st.tuples(nice_strings, st.lists(nice_strings)))

class StatefulDiscoveryTesting(GenericStateMachine):
    """
    State machine for testing Discovery.
    """
    def __init__(self):
        self.real = create_disco()
        self.fake = FakeDiscovery()

    def remove_strategy(self):
        def get_address(service_name):
            return st.tuples(st.just(service_name), st.sampled_from(
                self.fake.services[service_name]))
        return st.tuples(st.just("remove"), (
                st.sampled_from(list(self.fake.services.keys())).flatmap(get_address)))

    def steps(self):
        result = add_strategy | replace_strategy
        # Replace or add to a known service cluster:
        if self.fake.services:
            result |= st.tuples(st.just("replace"),
                                st.tuples(st.sampled_from(list(self.fake.services.keys())),
                                          st.lists(nice_strings)))
            result |= st.tuples(st.just("add"),
                                st.tuples(st.sampled_from(list(self.fake.services.keys())),
                                          nice_strings))
        # Remove a known address from known cluster:
        if not self.fake.is_empty():
            result |= self.remove_strategy()
        return result

    def create_node(self, address, service):
        """Create a node with consistent id."""
        node = create_node(address, service)
        node.id = address + "_" + service
        return node

    def execute_step(self, step):
        command, args = step
        if command == "add":
            service, address = args
            message = NodeActive(self.create_node(address, service))
            self.fake.add(service, address)
        elif command == "remove":
            service, address = args
            message = NodeExpired(self.create_node(address, service))
            self.fake.remove(service, address)
        elif command == "replace":
            service, addresses = args
            nodes = [self.create_node(address, service) for address in addresses]
            message = ReplaceCluster(service, SANDBOX_ENV, nodes)
            self.fake.replace(service, addresses)
        else:
            raise AssertionError("Unknown command.")

        self.real.onMessage(None, message)
        self.fake.compare(self.real)

StatefulDiscoveryTests = StatefulDiscoveryTesting.TestCase


class StaticDiscoverySourceTests(TestCase):
    """Tests for StaticDiscoverySource."""

    def setUp(self):
        self.runtime = fake_runtime()
        self.disco = Discovery(self.runtime)
        self.runtime.dispatcher.startActor(self.disco)

    def test_active(self):
        """The nodes the StaticRoutes was registered with are active."""
        nodes = [create_node("a", "service1"),
                 create_node("b", "service2")]
        static = StaticRoutes(nodes).create(self.disco, self.runtime)
        self.runtime.dispatcher.startActor(static)
        self.runtime.dispatcher.pump()

        self.assertEqual(knownNodes(self.disco, "service1", "sandbox"), [nodes[0]])
        self.assertEqual(knownNodes(self.disco, "service2", "sandbox"), [nodes[1]])

    def test_parseJSON(self):
        """
        Nodes encoded as JSON and loaded with StaticRoutes.parseJSON are registered
        as active.
        """
        static = StaticRoutes.parseJSON(dumps(
            [{"service": "service1", "address": "a", "version": "1.0",
              "environment": {"name": "myenv", "fallbackName": None},
              "id": "1234"},
             {"service": "service2", "address": "b", "version": "2.0",
              "environment": {"name": "myenv2", "fallbackName": None},
              "id": "4567"}]
        )).create(self.disco, self.runtime)

        self.runtime.dispatcher.startActor(static)
        self.runtime.dispatcher.pump()

        [node1] = knownNodes(self.disco, "service1", "myenv")
        self.assertEqual((node1.address, node1.version), ("a", "1.0"))
        [node2] = knownNodes(self.disco, "service2", "myenv2")
        self.assertEqual((node2.address, node2.version), ("b", "2.0"))


class DiscoveryProtocolTests(TestCase):
    """Tests for the Discovery protocol.

    Originally part of mdk_test.q.
    """

    def setUp(self):
        self.connector = MDKConnector(start=False)

    def pump(self):
        self.connector.pump()

    ########/
    # Helpers

    def expectOpen(self, ws_actor):
        return self.connector.connect(ws_actor)

    def expectActive(self, ws_actor):
        self.pump()
        return self.connector.expectSerializable(
            ws_actor, "mdk_discovery.protocol.Active")

    def assertEqualNodes(self, expected, actual):
        self.assertEqual(expected.service, actual.service)
        self.assertEqual(expected.address, actual.address)
        self.assertEqual(expected.version, actual.version)
        self.assertEqual(expected.properties, actual.properties)

    def createDisco(self):
        return self.connector.mdk._disco

    def startDisco(self):
        self.connector.mdk.start()
        self.pump()
        ws_actor = self.connector.expectSocket()
        self.connector.connect(ws_actor)
        return ws_actor

    ########/
    # Tests

    def testStart(self):
        sev = self.startDisco()
        self.assertFalse(sev == None)

    def testFailedStart(self):
        # ...
        pass

    def testRegisterPreStart(self):
        disco = self.createDisco()

        node = Node()
        node.id = str(uuid4())
        node.service = "svc"
        node.address = "addr"
        node.version = "1.2.3"
        disco.register(node)

        sev = self.startDisco()

        active = self.expectActive(sev)
        self.assertFalse(active == None)
        self.assertEqualNodes(node, active.node)

    def testRegisterPostStart(self):
        disco = self.createDisco()
        sev = self.startDisco()

        node = Node()
        node.id = str(uuid4())
        node.service = "svc"
        node.address = "addr"
        node.version = "1.2.3"
        disco.register(node)

        active = self.expectActive(sev)
        self.assertFalse(active == None)
        self.assertEqualNodes(node, active.node)

    def doActive(self, sev, svc, addr, version):
        active = Active()
        active.node = Node()
        active.node.id = str(uuid4())
        active.node.service = svc
        active.node.address = addr
        active.node.version = version
        sev.send(active.encode())
        self.pump()
        return active.node

    def testResolvePreStart(self):
        disco = self.createDisco()

        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqual(False, promise.value().hasValue())

        sev = self.startDisco()
        self.assertFalse(sev == None)

        node = self.doActive(sev, "svc", "addr", "1.2.3")

        self.assertEqualNodes(node, promise.value().getValue())

    def testResolvePostStart(self):
        disco = self.createDisco()
        sev = self.startDisco()

        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqual(False, promise.value().hasValue())

        node = self.doActive(sev, "svc", "addr", "1.2.3")

        self.assertEqualNodes(node, promise.value().getValue())

    def testResolveAfterNotification(self):
        disco = self.createDisco()
        sev = self.startDisco()

        node = self.doActive(sev, "svc", "addr", "1.2.3")

        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(node, promise.value().getValue())

    # This variant caught a bug in the code, so it's useful to have all of
    # these even though they're seemingly similar.
    def testResolveBeforeAndBeforeNotification(self):
        disco = self.createDisco()
        sev = self.startDisco()
        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)
        promise2 = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqual(False, promise.value().hasValue())
        self.assertEqual(False, promise2.value().hasValue())

        node = self.doActive(sev, "svc", "addr", "1.2.3")

        self.assertEqualNodes(node, promise.value().getValue())
        self.assertEqualNodes(node, promise2.value().getValue())

    def testResolveBeforeAndAfterNotification(self):
        disco = self.createDisco()
        sev = self.startDisco()
        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)

        node = self.doActive(sev, "svc", "addr", "1.2.3")

        promise2 = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(node, promise.value().getValue())
        self.assertEqualNodes(node, promise2.value().getValue())

    def testResolveDifferentActive(self):
        disco = self.createDisco()
        sev = self.startDisco()

        node = self.doActive(sev, "svc", "addr", "1.2.3")
        self.doActive(sev, "svc2", "addr", "1.2.3")

        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(node, promise.value().getValue())

    def testResolveVersionAfterActive(self):
        disco = self.createDisco()
        sev = self.startDisco()

        n1 = self.doActive(sev, "svc", "addr1.0", "1.0.0")
        n2 = self.doActive(sev, "svc", "addr1.2.3", "1.2.3")

        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(n1, promise.value().getValue())
        promise = disco.resolve("svc", "1.1", SANDBOX_ENV)
        self.assertEqualNodes(n2, promise.value().getValue())

    def testResolveVersionBeforeActive(self):
        disco = self.createDisco()
        sev = self.startDisco()

        p1 = disco.resolve("svc", "1.0", SANDBOX_ENV)
        p2 = disco.resolve("svc", "1.1", SANDBOX_ENV)

        n1 = self.doActive(sev, "svc", "addr1.0", "1.0.0")
        n2 = self.doActive(sev, "svc", "addr1.2.3", "1.2.3")

        self.assertEqualNodes(n1, p1.value().getValue())
        self.assertEqualNodes(n2, p2.value().getValue())

    def testResolveBreaker(self):
        disco = self.createDisco()
        sev = self.startDisco()

        n1 = self.doActive(sev, "svc", "addr1", "1.0.0")
        n2 = self.doActive(sev, "svc", "addr2", "1.0.0")

        p = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(n1, p.value().getValue())
        p = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(n2, p.value().getValue())

        failed = p.value().getValue()
        fpfactory = disco._fpfactory
        for idx in range(fpfactory.threshold):
            failed.failure()

        p = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(n1, p.value().getValue())
        p = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqualNodes(n1, p.value().getValue())

    def testLoadBalancing(self):
        disco = self.createDisco()
        sev = self.startDisco()

        promise = disco.resolve("svc", "1.0", SANDBOX_ENV)
        self.assertEqual(False, promise.value().hasValue())

        active = Active()

        count = 10
        for idx in range(count):
            active.node = Node()
            active.node.id = str(uuid4())
            active.node.service = "svc"
            active.node.address = "addr" + str(idx)
            active.node.version = "1.2.3"
            sev.send(active.encode())
            idx = idx + 1
        self.connector.pump()

        for idx in range(count*10):
            node = disco.resolve("svc", "1.0", SANDBOX_ENV).value().getValue()
            assert node is not None
            self.assertEqual("addr" + str(idx % count), node.address)

    def testReconnect(self):
        """
        Upon disconnecting the client will:

        1. Reconnect.
        2. Resend all registered nodes.
        """
        disco = self.createDisco()
        ws_actor = self.startDisco()
        node = create_node("myaddress")
        disco.register(node)
        self.connector.pump()
        active = self.expectActive(ws_actor)
        self.assertFalse(active == None)
        self.assertEqualNodes(node, active.node)

        # Disconnect:
        ws_actor.close()
        del ws_actor

        # It should reconnect:
        self.connector.advance_time(1)
        self.connector.pump()
        ws_actor2 = self.connector.expectSocket()
        self.connector.connect(ws_actor2)
        # And it should resent registration message:
        active = self.expectActive(ws_actor2)
        self.assertFalse(active == None)
        self.assertEqualNodes(node, active.node)

    # Unexpected messages are ignored.
    def testUnexpectedMessage(self):
        sev = self.startDisco()
        sev.send("{\"type\": \"UnknownMessage\"}")
        self.pump()
        self.assertEqual("CONNECTED", sev.state)

    def testStop(self):
        timeService = self.connector.runtime.getTimeService()
        disco = self.createDisco()
        sev = self.startDisco()

        node = Node()
        node.id = str(uuid4())
        node.service = "svc"
        node.version = "1.2.3"
        node.address = "addr"
        disco.register(node)

        active = self.expectActive(sev)
        self.assertNotEqual(active, None)

        self.connector.mdk.stop()
        # Might take some cleanup to stop everything:
        timeService.advance(15.0)
        self.pump()
        self.pump()
        self.pump()
        self.pump()

        # At this point we should have nothing scheduled and socket should be
        # closed:
        ws = self.connector.runtime.getWebSocketsService()
        self.assertEqual([sev], ws.fakeActors) # Only the one connection
        self.assertEqual("DISCONNECTED", sev.state)
        self.assertEqual(0, timeService.scheduled())
