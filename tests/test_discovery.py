"""
Tests for Discovery.

Additional tests can be found in quark/tests/mdk_test.q.
"""

from __future__ import absolute_import

from unittest import TestCase

from .common import fake_runtime

from mdk_discovery import (
    Discovery, Node, NodeActive, NodeExpired, ReplaceCluster,
)


class DiscoveryTests(TestCase):
    """Tests for Discovery."""

    def create_disco(self):
        """
        Create a new Discovery instance.
        """
        runtime = fake_runtime()
        disco = Discovery(runtime)
        disco.onStart(runtime.dispatcher)
        return disco

    def create_node(self, address):
        """Create a new Node."""
        node = Node()
        node.service = "myservice"
        node.version = "1.0"
        node.address = address
        node.properties = {}
        return node

    def assertNodesEqual(self, a, b):
        """The two Nodes have the same values."""
        self.assertEqual((a.version, a.address, a.service, a.properties),
                         (b.version, b.address, b.service, b.properties))

    def resolve(self, disco, service, version):
        """Resolve a service to a Node."""
        return disco._resolve(service, version).value().getValue()

    def test_active(self):
        """NodeActive adds a Node to Discovery."""
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        self.assertEqual(disco.knownNodes("myservice"), [node])

    def test_resolve(self):
        """resolve() returns a Node matching an active one."""
        disco = self.create_disco()
        node = self.create_node("somewhere")
        node.properties = {"x": 1}
        disco.onMessage(None, NodeActive(node))
        resolved = self.resolve(disco, "myservice", "1.0")
        self.assertEqual(
            (resolved.version, resolved.address, resolved.service, resolved.properties),
            ("1.0", "somewhere", "myservice", {"x": 1}))

    def test_activeUpdates(self):
        """NodeActive updates a Node with same address to new version and properties."""
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        node2 = self.create_node("somewhere")
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
        disco = self.create_disco()
        result = []
        promise = disco._resolve("myservice", "1.0")
        promise.andThen(result.append)
        self.assertFalse(result)

        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        self.assertNodesEqual(result[0], node)

    def test_expired(self):
        """NodeExpired removes a Node from Discovery."""
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        disco.onMessage(None, NodeExpired(node))
        self.assertEqual(disco.knownNodes("myservice"), [])

    def test_expiredUnknown(self):
        """NodeExpired does nothing for unknown Node."""
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeExpired(node))
        self.assertEqual(disco.knownNodes("myservice"), [])

    def test_replace(self):
        """
        ReplaceCluster replaces the contents of a Cluster (collection of Nodes for
        the same service name).
        """
        disco = self.create_disco()
        node1 = self.create_node("somewhere")
        node2 = self.create_node("somewhere2")
        node3 = self.create_node("somewhere3")
        node4 = self.create_node("somewhere4")
        disco.onMessage(None, NodeActive(node1))
        disco.onMessage(None, NodeActive(node2))
        disco.onMessage(None, ReplaceCluster("myservice", [node3, node4]))
        self.assertItemsEqual(disco.knownNodes("myservice"), [node3, node4])

    def test_replaceEmpty(self):
        """
        ReplaceCluster register nodes when the Discovery source is empty.
        """
        disco = self.create_disco()
        node1 = self.create_node("somewhere")
        node2 = self.create_node("somewhere2")
        disco.onMessage(None, ReplaceCluster("myservice", [node1, node2]))
        self.assertItemsEqual(disco.knownNodes("myservice"), [node1, node2])

    def test_replaceTriggersWaitingPromises(self):
        """
        ReplaceCluster causes waiting resolve() Promises to get a Node.
        """
        disco = self.create_disco()
        result = []
        promise = disco._resolve("myservice", "1.0")
        promise.andThen(result.append)
        self.assertFalse(result)

        node = self.create_node("somewhere")
        disco.onMessage(None, ReplaceCluster("myservice", [node]))
        self.assertNodesEqual(result[0], node)

    def test_activeDoesNotMutate(self):
        """
        A resolved Node is not mutated by a new NodeActive for same address.
        """
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = self.resolve(disco, "myservice", "1.0")

        node2 = self.create_node("somewhere")
        node2.version = "1.3"
        disco.onMessage(None, NodeActive(node2))
        self.assertEqual(resolved_node.version, "1.0")

    def test_replaceDoesNotMutate(self):
        """
        A resolved Node is not mutated by a new ReplaceCluster containing a Node
        with the same address.
        """
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = self.resolve(disco, "myservice", "1.0")

        node2 = self.create_node("somewhere")
        node2.version = "1.3"
        disco.onMessage(None, ReplaceCluster("myservice", [node2]))
        self.assertEqual(resolved_node.version, "1.0")

    def test_nodeCircuitBreaker(self):
        """success()/failure() enable and disable the Node."""
        disco = self.create_disco()
        node = self.create_node("somewhere")
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
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = self.resolve(disco, "myservice", "1.0")
        # Uh-oh it's a pretty broken node:
        for i in range(10):
            resolved_node.failure()

        node = self.create_node("somewhere")
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
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        resolved_node = self.resolve(disco, "myservice", "1.0")
        # Uh-oh it's a pretty broken node:
        for i in range(10):
            resolved_node.failure()

        node = self.create_node("somewhere")
        disco.onMessage(None, ReplaceCluster("myservice", [node]))
        resolved_node2 = self.resolve(disco, "myservice", "1.0")
        self.assertEqual(resolved_node2, None)
        resolved_node.success()
        self.assertNodesEqual(self.resolve(disco, "myservice", "1.0"), node)
