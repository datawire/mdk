"""
Tests for Tracing.
"""

from __future__ import absolute_import

from unittest import TestCase

from mdk_protocol import SharedContext
from mdk_tracing.protocol import LogEvent
from .common import MDKConnector


class TracingProtocolTests(TestCase):
    """Tests for the Tracing protocol.

    Originally part of mdk_test.q.
    """

    def setUp(self):
        self.connector = MDKConnector(start=False)

    def pump(self):
        self.connector.pump()

    def expectLogEvent(self, ws_actor):
        return self.connector.expectSerializable(
            ws_actor, "mdk_tracing.protocol.LogEvent")

    def expectSubscribe(self, ws_actor):
        return self.connector.expectSerializable(
            ws_actor, "mdk_tracing.protocol.Subscribe")

    #################
    # Tests
    def newTracer(self):
        return self.connector.mdk._tracer

    def startTracer(self):
        self.connector.mdk.start()
        self.pump()
        ctx = SharedContext()
        self.connector.mdk._tracer.log(
            ctx, "procUUID", "DEBUG", "blah", "testing...")
        self.pump()
        ws_actor = self.connector.expectSocket()
        self.assertFalse(ws_actor == None)
        self.connector.connect(ws_actor)
        return ws_actor

    def testLog(self):
        sev = self.startTracer()
        evt = self.expectLogEvent(sev)
        self.assertFalse(evt == None)
        self.assertEqual("DEBUG", evt.level)
        self.assertEqual("blah", evt.category)
        self.assertEqual("testing...", evt.text)

    # Unexpected messages are ignored.
    def testUnexpectedMessage(self):
        sev = self.startTracer()
        sev.send("{\"type\": \"UnknownMessage\"}")
        self.pump()
        self.assertEqual("CONNECTED", sev.state)

    def testSubscribe(self):
        tracer = self.newTracer()
        events = []
        tracer.subscribe(events.append)
        self.pump()
        sev = self.startTracer()
        sev.swallowLogMessages()
        sub = self.expectSubscribe(sev)
        self.assertFalse(sub == None)
        e = LogEvent()
        e.text = "asdf"
        sev.send(e.encode())
        self.pump()
        self.assertEqual(1, len(events))
        evt = events[0]
        self.assertEqual("asdf", evt.text)
