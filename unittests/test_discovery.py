"""
Tests for Discovery.

Additional tests can be found in quark/tests/mdk_test.q.
"""

from __future__ import absolute_import
from builtins import range
from builtins import object

from unittest import TestCase

from hypothesis.stateful import GenericStateMachine
from hypothesis import strategies as st

from .common import fake_runtime

from mdk_discovery import (
    Discovery, Node, NodeActive, NodeExpired, ReplaceCluster,
    CircuitBreakerFactory, StaticRoutes,
)


def create_disco():
    """
    Create a new Discovery instance.
    """
    runtime = fake_runtime()
    disco = Discovery(runtime)
    disco.onStart(runtime.dispatcher)
    return disco


def create_node(address, service="myservice"):
    """Create a new Node."""
    node = Node()
    node.service = service
    node.version = "1.0"
    node.address = address
    node.properties = {}
    return node


class DiscoveryTests(TestCase):
    """Tests for Discovery."""

    def assertNodesEqual(self, a, b):
        """The two Nodes have the same values."""
        self.assertEqual((a.version, a.address, a.service, a.properties),
                         (b.version, b.address, b.service, b.properties))

    def resolve(self, disco, service, version):
        """Resolve a service to a Node."""
        return disco._resolve(service, version).value().getValue()

    def test_active(self):
        """NodeActive adds a Node to Discovery."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        self.assertEqual(disco.knownNodes("myservice"), [node])

    def test_resolve(self):
        """resolve() returns a Node matching an active one."""
        disco = create_disco()
        node = create_node("somewhere")
        node.properties = {"x": 1}
        disco.onMessage(None, NodeActive(node))
        resolved = self.resolve(disco, "myservice", "1.0")
        self.assertEqual(
            (resolved.version, resolved.address, resolved.service, resolved.properties),
            ("1.0", "somewhere", "myservice", {"x": 1}))

    def test_activeUpdates(self):
        """NodeActive updates a Node with same address to new version and properties."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        node2 = create_node("somewhere")
        node2.version = "1.7"
        node2.properties = {"a": 123}
        disco.onMessage(None, NodeActive(node2))
        self.assertEqual(disco.knownNodes("myservice"), [node2])
        resolved = self.resolve(disco, "myservice", "1.7")
        self.assertEqual((resolved.version, resolved.properties),
                         ("1.7", {"a": 123}))

    def test_activeTriggersWaitingPromises(self):
        """
        NodeActive causes waiting resolve() Promises to get a Node.
        """
        disco = create_disco()
        result = []
        promise = disco._resolve("myservice", "1.0")
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
        self.assertEqual(disco.knownNodes("myservice"), [])

    def test_expiredUnknown(self):
        """NodeExpired does nothing for unknown Node."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeExpired(node))
        self.assertEqual(disco.knownNodes("myservice"), [])

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
        disco.onMessage(None, ReplaceCluster("myservice", [node3, node4]))
        self.assertEqual(disco.knownNodes("myservice"), [node3, node4])

    def test_replaceEmpty(self):
        """
        ReplaceCluster register nodes when the Discovery source is empty.
        """
        disco = create_disco()
        node1 = create_node("somewhere")
        node2 = create_node("somewhere2")
        disco.onMessage(None, ReplaceCluster("myservice", [node1, node2]))
        self.assertEqual(disco.knownNodes("myservice"), [node1, node2])

    def test_replaceTriggersWaitingPromises(self):
        """
        ReplaceCluster causes waiting resolve() Promises to get a Node.
        """
        disco = create_disco()
        result = []
        promise = disco._resolve("myservice", "1.0")
        promise.andThen(result.append)
        self.assertFalse(result)

        node = create_node("somewhere")
        disco.onMessage(None, ReplaceCluster("myservice", [node]))
        self.assertNodesEqual(result[0], node)

    def test_activeDoesNotMutate(self):
        """
        A resolved Node is not mutated by a new NodeActive for same address.
        """
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = self.resolve(disco, "myservice", "1.0")

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
        resolved_node = self.resolve(disco, "myservice", "1.0")

        node2 = create_node("somewhere")
        node2.version = "1.3"
        disco.onMessage(None, ReplaceCluster("myservice", [node2]))
        self.assertEqual(resolved_node.version, "1.0")

    def test_nodeCircuitBreaker(self):
        """success()/failure() enable and disable the Node."""
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = self.resolve(disco, "myservice", "1.0")

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
        resolved_node = self.resolve(disco, "myservice", "1.0")
        # Uh-oh it's a pretty broken node:
        for i in range(10):
            resolved_node.failure()

        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node2 = self.resolve(disco, "myservice", "1.0")
        self.assertEqual(resolved_node2, None)
        resolved_node.success()
        self.assertNodesEqual(self.resolve(disco, "myservice", "1.0"), node)

    def test_replaceDoesNotDisableCircuitBreaker(self):
        """
        If a Node has been disabled by a CircuitBreaker then ReplaceCluster with
        same Node doesn't re-enable it.
        """
        disco = create_disco()
        node = create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = self.resolve(disco, "myservice", "1.0")
        # Uh-oh it's a pretty broken node:
        for i in range(10):
            resolved_node.failure()

        node = create_node("somewhere")
        disco.onMessage(None, ReplaceCluster("myservice", [node]))
        resolved_node2 = self.resolve(disco, "myservice", "1.0")
        self.assertEqual(resolved_node2, None)
        resolved_node.success()
        self.assertNodesEqual(self.resolve(disco, "myservice", "1.0"), node)


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
        for name, cluster in list(real_discovery.services.items()):
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

    def execute_step(self, step):
        command, args = step
        if command == "add":
            service, address = args
            message = NodeActive(create_node(address, service))
            self.fake.add(service, address)
        elif command == "remove":
            service, address = args
            message = NodeExpired(create_node(address, service))
            self.fake.remove(service, address)
        elif command == "replace":
            service, addresses = args
            nodes = [create_node(address, service) for address in addresses]
            message = ReplaceCluster(service, nodes)
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
        self.nodes = [create_node("a", "service1"),
                      create_node("b", "service2")]
        self.static = StaticRoutes(self.nodes).create(self.disco, self.runtime)
        self.runtime.dispatcher.startActor(self.static)

    def test_active(self):
        """The nodes the StaticRoutes was registered with are active."""
        self.assertEqual(self.disco.knownNodes("service1"), [self.nodes[0]])
        self.assertEqual(self.disco.knownNodes("service2"), [self.nodes[1]])

