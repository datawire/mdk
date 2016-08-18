"""
Tests for the MDK public API that are easier to do in Python.
"""

from unittest import TestCase
from tempfile import mkdtemp

from mdk import MDKImpl
from mdk_runtime import fakeRuntime


class MDKInitializationTestCase(TestCase):
    """
    Tests for top-level MDK API startup.
    """
    def test_no_datawire_token(self):
        """
        If DATAWIRE_TOKEN is not set neither the TracingClient nor the DiscoClient
        are started.
        """
        # Disable connecting to our Discovery server:
        runtime = fakeRuntime()
        runtime.getEnvVarsService().set("MDK_DISCOVERY_SOURCE", "synapse:path=" + mkdtemp())

        # Start the MDK:
        mdk = MDKImpl(runtime)
        mdk.start()

        # Do a bunch of logging:
        session = mdk.session()
        session.info("category", "hello!")
        session.error("category", "ono")
        session.warn("category", "gazoots")
        session.critical("category", "aaaaaaa")
        session.debug("category", "behold!")

        # Time passes...
        scheduleService = runtime.getScheduleService()
        for i in range(10):
            scheduleService.advance(1.0)
            scheduleService.pump()

        # No WebSocket connections made:
        self.assertFalse(runtime.getWebSocketsService().fakeActors)

