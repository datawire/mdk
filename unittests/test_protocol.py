"""
Tests for the MDK low-level protocol code.
"""

from collections import deque

import hypothesis.strategies as st
from hypothesis import given, assume

from mdk_protocol import SendWithAcks


class SendToServer(object):
    """
    Implement the SendAckableEvent interface.
    """
    def __init__(self, simulator):
        self.simulator = simulator

    def send(self, event):
        self.simulator._send_to_server(event)


class Payload(object):
    """
    Implement the AckablePayload interface.
    """
    def __init__(self, message):
        self.message = message

    def getTimestamp(self):
        return 1


class NetworkSimulator(object):
    """
    Simulate connection between SendWithAcks and a server.
    """
    def __init__(self):
        self.server_received = set()
        self.client = SendWithAcks()

    def _send_to_server(self, event):
        """
        Send a AckableEvent to the server.
        """
        self.connection_to_server.appendleft(event)

    def reconnect(self):
        """
        Disconnect client from server and then reconnect.
        """
        # Wipe existing connection, if any:
        self.connection_to_server = deque()
        self.connection_to_client = deque()
        # Notify client:
        self.client.onConnected(SendToServer(self))

    def tick(self):
        """
        One pseudo-second has passed.
        """
        # Connection delivers acks to client, if there is any.
        if self.connection_to_client:
            ack = self.connection_to_client.pop()
            self.client.onAck(ack)

        # Connection delivers message to server, if there is any.  The server
        # then acks it. Do this after ack delivery so it takes another tick for
        # acks to be delivered.
        if self.connection_to_server:
            message = self.connection_to_server.pop()
            self.server_received.add(message.payload)
            self.connection_to_client.appendleft(message.sequence)

        # Tell client time has passed:
        self.client.onPump(SendToServer(self))


def test_sendWithAcks_delivery():
    """
    Demonstrate that sendWithAcks algorithm delivers messages even though
    connections are dropped.

    Basic test setup:

    1. SendWithAcks is told to send 10 messages.
    2. Messages get added to a Connection.
    3. Once a (fake) second a message is moved from Connection to Server.
    4. Once a second the Server sends an Ack to Connection.
    5. Once a second the Acks from Connection are delivered to SendWithAcks.

    Every once in a while the Connection disconnects, and everything in its
    buffers is wiped and never delivered. It then reconnects.

    At the end of large-number-of-seconds all messages should have been
    delivered to Server and SendWithAcks should have no buffered messages.
    """
    simulator = NetworkSimulator()
    messages = set(Payload("message{}".format(i)) for i in range(10))
    for m in messages:
        simulator.client.send("my_type", m)

    simulator.reconnect()
    for _ in range(10000):
        simulator.tick()

    assert simulator.server_received == messages
    assert len(simulator.client._buffered) == 0
    assert len(simulator.client._inFlight) == 0
