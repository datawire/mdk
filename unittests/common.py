"""
Common utilities.
"""

from json import loads
from uuid import uuid4

from mdk_runtime import fakeRuntime
from mdk_discovery import CircuitBreakerFactory, Node
from mdk_protocol import Serializable
from mdk import MDKImpl, _parseEnvironment
from mdk_tracing import FakeTracer


def fake_runtime():
    """
    Create a fake runtime suitably configured for MDK usage.
    """
    runtime = fakeRuntime()
    runtime.dependencies.registerService(
            "failurepolicy_factory", CircuitBreakerFactory(runtime))
    return runtime


def create_node(address, service="myservice", environment="sandbox"):
    """Create a new Node."""
    node = Node()
    node.service = service
    node.version = "1.0"
    node.address = address
    node.properties = {"datawire_nodeId": str(uuid4())}
    node.environment = _parseEnvironment(environment)
    return node


SANDBOX_ENV = _parseEnvironment("sandbox")


def create_mdk_with_faketracer(environment="sandbox"):
    """Create an MDK with a FakeTracer.

    Returns (mdk, fake_tracer).
    """
    runtime = fakeRuntime()
    tracer = FakeTracer()
    runtime.dependencies.registerService("tracer", tracer)
    runtime.getEnvVarsService().set("MDK_DISCOVERY_SOURCE", "static:nodes={}")
    runtime.getEnvVarsService().set("MDK_ENVIRONMENT", environment)
    mdk = MDKImpl(runtime)
    mdk.start()
    return mdk, tracer

class MDKConnector(object):
    """Manage an interaction with fake remote server."""

    URL = "ws://localhost:1234/"

    def __init__(self, failurepolicy_factory=None, env={}, start=True):
        self.runtime = fakeRuntime()
        env_vars = self.runtime.getEnvVarsService()
        for key, value in env.items():
            env_vars.set(key, value)
        env_vars.set("DATAWIRE_TOKEN", "xxx");
        env_vars.set("MDK_SERVER_URL", self.URL);
        if failurepolicy_factory is not None:
            self.runtime.dependencies.registerService(
                "failurepolicy_factory", failurepolicy_factory)
        self.mdk = MDKImpl(self.runtime)
        if start:
            self.mdk.start()
            self.pump()

    def pump(self):
        """Deliver scheduled events."""
        self.runtime.getTimeService().pump()

    def advance_time(self, seconds):
        """Advance the clock."""
        ts = self.runtime.getTimeService()
        ts.advance(seconds)
        ts.pump()
        ts.pump()

    def expectSocket(self):
        """Return the FakeWSActor we expect to have connected to a URL."""
        ws = self.runtime.getWebSocketsService()
        actor = ws.lastConnection()
        assert actor.url.startswith(self.URL)
        return actor

    def expectSerializable(self, fake_wsactor, expected_type):
        """Return the last sent message of given type."""
        msg = fake_wsactor.expectTextMessage()
        assert msg is not None
        json = loads(msg)
        evt = Serializable.decodeClassName(expected_type, msg)
        assert json["type"] == evt._json_type
        return evt

    def connect(self, fake_wsactor):
        """Connect and then return the last sent Open message."""
        fake_wsactor.accept()
        self.pump()
        return self.expectSerializable(fake_wsactor, "mdk_protocol.Open")

    def expectInteraction(self, test, fake_wsactor, session,
                          failed_nodes, succeeded_nodes):
        """Assert an InteractionEvent was sent, and return it."""
        interaction = self.expectSerializable(
            fake_wsactor, "mdk_metrics.InteractionEvent")
        test.assertEqual(interaction.node, self.mdk.procUUID)
        test.assertEqual(interaction.session, session._context.traceId)
        expected = {node.properties["datawire_nodeId"]: 1
                    for node in succeeded_nodes}
        for node in failed_nodes:
            expected[node.properties["datawire_nodeId"]] = 0
        test.assertEqual(interaction.results, expected)
        return interaction
