"""
Tests for Discovery.

Additional tests can be found in quark/tests/mdk_test.q.
"""

from unittest import TestCase

from mdk_runtime import fakeRuntime
from mdk_discovery import (
    Discovery, Node, NodeActive, NodeExpired, ReplaceCluster, CircuitBreakerFactory,
)


class DiscoveryTests(TestCase):
    """Tests for Discovery."""

    def create_disco(self):
        """
        Create a new Discovery instance.
        """
        runtime = fakeRuntime()
        runtime.dependencies.registerService(
            "failurepolicy_factory", CircuitBreakerFactory())
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

    def test_active(self):
        """NodeActive adds a Node to Discovery."""
        disco = self.create_disco()
        node = self.create_node("somewhere")
        disco.onMessage(None, NodeActive(node))
        self.assertEqual(disco.knownNodes("myservice"), [node])

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
        self.assertEqual(result, [node])

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
        self.assertEqual(result, [node])
