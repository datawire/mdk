"""Tests for the Discovery MCP protocol."""

from unittest import TestCase

from mdk_discovery.protocol import Clear

from .common import MDKConnector


class DiscoveryProtocolTests(TestCase):
    """Tests for the Discovery protocol.

    Some tests are still in mdk_test.q, for now.
    """
    def test_no_sent_active_until_clear(self):
        """
        Until a Clear message is received from the server we don't sent any Active
        messages.
        """
        connector = MDKConnector()
        ws_actor = connector.expectSocket()
        connector.connect(ws_actor)

        connector.mdk.register("hello", "1.0", "address")
        connector.pump()
        self.assertEqual(ws_actor.uninspectedSentMessages(), 0)
        ws_actor.send(Clear().encode())
        connector.pump()
        active = connector.expectSerializable(
            ws_actor, "mdk_discovery.protocol.Active")
        self.assertEqual(active.node.service, "hello")
