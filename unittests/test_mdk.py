"""
Tests for the MDK public API that are easier to do in Python.
"""
from time import time
from builtins import range
from past.builtins import unicode

from unittest import TestCase
from tempfile import mkdtemp
from collections import Counter

import hypothesis.strategies as st
from hypothesis import given, assume

from mdk import MDKImpl
from mdk_runtime import fakeRuntime
from mdk_discovery import (
    ReplaceCluster, NodeActive, RecordingFailurePolicyFactory,
)
from mdk_protocol import Close, ProtocolError

from .common import (
    create_node, SANDBOX_ENV, MDKConnector, create_mdk_with_faketracer,
)


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


def add_bools(list_of_lists):
    """
    Given recursive list that can contain other lists, return tuple of that plus
    a booleans strategy for each list.
    """
    l = []
    def count(recursive):
        l.append(1)
        for child in recursive:
            if isinstance(child, list):
                count(child)
    count(list_of_lists)
    return st.tuples(st.just(list_of_lists), st.tuples(*[st.sampled_from([True, False]) for i in l]))


class InteractionTestCase(TestCase):
    """Tests for the Session interaction API."""

    def init(self):
        """Initialize an empty environment."""
        self.connector = MDKConnector(RecordingFailurePolicyFactory(), real_msg=True)
        self.runtime = self.connector.runtime
        self.mdk = self.connector.mdk
        self.disco = self.mdk._disco
        # Create a session:
        self.session = self.mdk.session()

    def setUp(self):
        self.init()

        # Register some nodes:
        self.node1 = create_node("a1", "service1")
        self.node2 = create_node("a2", "service1")
        self.node3 = create_node("b1", "service2")
        self.node4 = create_node("b2", "service2")
        self.all_nodes = set([self.node1, self.node2, self.node3, self.node4])

        self.disco.onMessage(None, ReplaceCluster("service1", SANDBOX_ENV,
                                                  [self.node1, self.node2]))
        self.disco.onMessage(None, ReplaceCluster("service2", SANDBOX_ENV,
                                                  [self.node3, self.node4]))

    def assertPolicyState(self, policies, successes, failures):
        """
        Assert that the given FailurePolicy instances has the given number of
        success() and failure() calls.
        """
        for policy in policies:
            self.assertEqual((policy.successes, policy.failures),
                             (successes, failures))

    def test_successfulInteraction(self):
        """
        All nodes resolved within a successful interaction are marked as
        succeeding to connect.
        """
        self.session.start_interaction()
        node = self.session.resolve("service1", "1.0")
        another_node = self.session.resolve("service2", "1.0")
        self.session.finish_interaction()
        expected_successful = [self.disco.failurePolicy(node),
                               self.disco.failurePolicy(another_node)]
        expected_nothing = list(self.disco.failurePolicy(n) for n in
                                self.all_nodes if
                                n.address not in [node.address, another_node.address])
        self.assertPolicyState(expected_successful, 1, 0)
        self.assertPolicyState(expected_nothing, 0, 0)

    def test_failedInteraction(self):
        """All nodes resolved with a failing interaction are marked as failures."""
        self.session.start_interaction()
        node = self.session.resolve("service1", "1.0")
        another_node = self.session.resolve("service2", "1.0")
        self.session.fail_interaction("OHNO")
        self.session.finish_interaction()
        expected_failed = [self.disco.failurePolicy(node),
                           self.disco.failurePolicy(another_node)]
        expected_nothing = list(self.disco.failurePolicy(n) for n in
                                self.all_nodes if
                                n.address not in [node.address, another_node.address])
        self.assertPolicyState(expected_failed, 0, 1)
        self.assertPolicyState(expected_nothing, 0, 0)

    def test_failedResetsInteraction(self):
        """
        Nodes resolved after a failing interaction are not marked as failed when
        finish is called.
        """
        self.session.start_interaction()
        node = self.session.resolve("service1", "1.0")
        self.session.fail_interaction("OHNO")
        another_node = self.session.resolve("service2", "1.0")
        self.session.finish_interaction()
        expected_failed = [self.disco.failurePolicy(node)]
        expected_succeeded = [self.disco.failurePolicy(another_node)]
        expected_nothing = list(self.disco.failurePolicy(n) for n in
                                self.all_nodes if
                                n.address not in [node.address, another_node.address])
        self.assertPolicyState(expected_failed, 0, 1)
        self.assertPolicyState(expected_succeeded, 1, 0)
        self.assertPolicyState(expected_nothing, 0, 0)

    def test_finishedResetsInteraction(self):
        """
        Each new interaction allows marking Nodes with new information.
        """
        self.session.start_interaction()
        node = self.session.resolve("service1", "1.0")
        self.session.fail_interaction("OHNO")
        self.session.finish_interaction()

        self.session.start_interaction()
        # Resolve same node again:
        while True:
            another_node = self.session.resolve("service1", "1.0")
            if node.address == another_node.address:
                break
        self.session.finish_interaction()

        self.assertPolicyState([self.disco.failurePolicy(node)], 1, 1)

    @given(st.recursive(st.text(alphabet="abcd", min_size=1, max_size=3),
                        st.lists).flatmap(add_bools))
    def test_nestedInteractions(self, values):
        """
        Nested interactions operate independently of parent interactions.

        :param values: a two-tuple composed of:
           - a recursive list of unicode and other recursive lists - list start
             means begin interaction, string means node resolve, list end means
             finish interaction.
           - list of False/True; True means failed interaction
        """
        requested_interactions, failures = values
        failures = iter(failures)
        assume(not isinstance(requested_interactions, unicode))
        self.init()
        ws_actor = self.connector.expectSocket()
        self.connector.connect(ws_actor)

        failures = iter(failures)
        created_services = {}
        expected_success_nodes = Counter()
        expected_failed_nodes = Counter()

        def run_interaction(children):
            should_fail = next(failures)
            failed = []
            succeeded = []
            self.session.start_interaction()
            for child in children:
                if isinstance(child, unicode):
                    # Make sure disco knows about the node:
                    if child in created_services:
                        node = created_services[child]
                    else:
                        node = create_node(child, child)
                        created_services[child] = node
                    self.disco.onMessage(None, NodeActive(node))
                    # Make sure the child Node is resolved in the interaction
                    self.session.resolve(node.service, "1.0")
                    if should_fail:
                        expected_failed_nodes[node] += 1
                        failed.append(node)
                    else:
                        expected_success_nodes[node] += 1
                        succeeded.append(node)
                else:
                    run_interaction(child)
            if should_fail:
                self.session.fail_interaction("OHNO")
            self.session.finish_interaction()
            self.connector.advance_time(5.0) # Make sure interaction is sent
            ws_actor.swallowLogMessages()
            self.connector.expectInteraction(
                self, ws_actor, self.session, failed, succeeded)

        run_interaction(requested_interactions)
        for node in set(expected_failed_nodes) | set(expected_success_nodes):
            policy = self.disco.failurePolicy(node)
            self.assertEqual((policy.successes, policy.failures),
                             (expected_success_nodes[node],
                              expected_failed_nodes[node]))


class SessionDeadlineTests(TestCase):
    """Tests for the session deadline."""

    def setUp(self):
        """Initialize an empty environment."""
        # Initialize runtime and MDK:
        self.runtime = fakeRuntime()
        self.runtime.getEnvVarsService().set("DATAWIRE_TOKEN", "something")
        self.mdk = MDKImpl(self.runtime)
        self.mdk.start()
        self.session = self.mdk.session()

    def test_setDeadline(self):
        """A set deadline can be retrieved."""
        self.session.setDeadline(13.5)
        self.assertEqual(13.5, self.session.getRemainingTime())

    def test_notSetDeadline(self):
        """Deadline is null if not set."""
        self.assertEqual(None, self.session.getRemainingTime())

    def test_deadlineChangesAsTimePasses(self):
        """If time passes the deadline goes down."""
        self.session.setDeadline(13.5)
        self.runtime.getTimeService().advance(2.0)
        self.assertEqual(11.5, self.session.getRemainingTime())

    def test_setDeadlineTwice(self):
        """Deadlines can be decreased by setting, but not increased."""
        self.session.setDeadline(10.0)
        self.session.setDeadline(9.0)
        decreased = self.session.getRemainingTime()
        self.session.setDeadline(11.0)
        still_decreased = self.session.getRemainingTime()
        self.assertEqual((decreased, still_decreased), (9.0, 9.0))

    def test_serialization(self):
        """A serialized session preserves the deadline."""
        self.session.setDeadline(10.0)
        self.session.setProperty("xx", "yy")
        serialized = self.session.externalize()
        session2 = self.mdk.join(serialized)
        self.assertEqual(session2.getRemainingTime(), 10.0)

    def test_mdkDefault(self):
        """The MDK can set a default deadline for new sessions."""
        self.mdk.setDefaultDeadline(5.0)
        session = self.mdk.session()
        self.assertEqual(session.getRemainingTime(), 5.0)

    def test_mdkDefaultForJoinedSessions(self):
        """
        Deadlines for joined sessions are decreased to the MDK default deadline, but
        never increased.
        """
        session1 = self.mdk.session()
        session1.setDeadline(1.0)
        encoded1 = session1.externalize()

        session2 = self.mdk.session()
        session2.setDeadline(3.0)
        encoded2 = session2.externalize()

        self.mdk.setDefaultDeadline(2.0)
        self.assertEqual((1.0, 2.0),
                         (self.mdk.join(encoded1).getRemainingTime(),
                          self.mdk.join(encoded2).getRemainingTime()))

    def test_resolveNoDeadline(self):
        """
        If a deadline higher than 10 seconds was set, resolving still times out after
        10.0 seconds.
        """
        self.session.setDeadline(20.0)
        start = time()
        with self.assertRaises(Exception):
            self.session.resolve("unknown", "1.0")
        self.assertAlmostEqual(time() - start, 10.0, delta=1)

    def test_resolveLowerDeadline(self):
        """
        If a deadline lower than 10 seconds was set, resolving happens after the
        lower deadline.
        """
        self.session.setDeadline(3.0)
        start = time()
        with self.assertRaises(Exception):
            self.session.resolve("unknown", "1.0")
        self.assertAlmostEqual(time() - start, 3.0, delta=1)


class SessionTests(TestCase):
    """Tests for sessions."""

    def setUp(self):
        """Initialize an empty environment."""
        self.connector = MDKConnector(env={"MDK_ENVIRONMENT": "myenv"})
        self.runtime = self.connector.runtime
        self.mdk = self.connector.mdk

    def assertSessionHas(self, session, trace_id, clock_level, **properties):
        """
        Assert the given SessionImpl has the given trace, clock and properties.
        """
        self.assertEqual(session._context.traceId, trace_id)
        self.assertEqual(session._context.clock.clocks, clock_level)
        self.assertEqual(session._context.properties, properties)

    def test_newSession(self):
        """New sessions have different trace IDs."""
        session = self.mdk.session()
        session2 = self.mdk.session()
        self.assertSessionHas(session, session._context.traceId, [0])
        self.assertSessionHas(session2, session2._context.traceId, [0])
        self.assertNotEqual(session._context.traceId,
                            session2._context.traceId)

    def test_newSesssionEnvironment(self):
        """New sessions get their environment from the MDK."""
        session = self.mdk.session()
        assertEnvironmentEquals(self, session.getEnvironment(), "myenv", None)

    def test_sessionProperties(self):
        """Sessions have properties that can be set, checked and retrieved."""
        session = self.mdk.session()
        value = ["123", {"12": 123}]
        session.setProperty("key", value)
        session.setProperty("key2", "hello")
        self.assertEqual((session.getProperty("key"), session.getProperty("key2"),
                          session.hasProperty("key"), session.hasProperty("key2"),
                          session.hasProperty("nope")),
                         (value, "hello", True, True, False))

    def test_joinSession(self):
        """
        A joined session has some trace ID, clock level  properties
        as the encoded session.
        """
        session = self.mdk.session()
        session.setProperty("key", 456)
        session.setProperty("key2", [456, {"zoo": "foo"}])
        session2 = self.mdk.join(session.externalize())
        self.assertSessionHas(session2, session._context.traceId, [1, 0],
                              key=456, key2=[456, {"zoo": "foo"}])

    def test_joinSessionEnvironment(self):
        """
        A joined session gets its environment from the encoded session, not the MDK.
        """
        connector = MDKConnector(env={"MDK_ENVIRONMENT": "env2"})
        encoded_session = connector.mdk.session().externalize()
        session2 = self.mdk.join(encoded_session)
        assertEnvironmentEquals(self, session2.getEnvironment(), "env2", None)

    def test_childSession(self):
        """
        A child session has a new trace ID and clock level, but knows about the
        parent session's trace ID and clock level and inherits properties other
        than timeout.
        """
        session = self.mdk.session()
        session.setProperty("other", 123)
        session._context.tick()
        session._context.tick()
        session._context.tick()
        session.setTimeout(13.0)
        session2 = self.mdk.derive(session.externalize())
        self.assertNotEqual(session._context.traceId,
                            session2._context.traceId)
        self.assertEqual(session2.getRemainingTime(), None)
        self.assertSessionHas(session2, session2._context.traceId, [1],
                              other=123)


def assertEnvironmentEquals(test, environment, name, fallback):
    """
    Assert the given environment has the given name and fallback name.
    """
    test.assertEqual(environment.name, name)
    test.assertEqual(environment.fallbackName, fallback)


class ConnectionStartupShutdownTests(TestCase):
    """Tests for initial setup and shutdown of MCP connections."""
    def test_connection_node_identity(self):
        """
        Each connection to MCP sends an Open message with the same node identity.
        """
        connector = MDKConnector()
        ws_actor = connector.expectSocket()
        open = connector.connect(ws_actor)
        ws_actor.close()
        connector.advance_time(1)
        ws_actor2 = connector.expectSocket()
        # Should be new connection:
        self.assertNotEqual(ws_actor, ws_actor2)
        open2 = connector.connect(ws_actor2)
        self.assertEqual(open.nodeId,open2.nodeId)
        self.assertEqual(open.nodeId, connector.mdk.procUUID)

    def test_random_node_identity(self):
        """
        Node identity is randomly generated each time.
        """
        # XXX FIXME Short-circuit the test. Otherwise
        #   open2 = connector.connect(ws_actor2)
        # kills the test framework via
        #   runtime.fail("no remaining message found").
        # Obviously, need to investigate this further.
        assert False
        connector = MDKConnector()
        ws_actor = connector.expectSocket()
        open = connector.connect(ws_actor)
        connector2 = MDKConnector()
        ws_actor2 = connector2.expectSocket()
        open2 = connector.connect(ws_actor2)
        self.assertNotEqual(open.nodeId, open2.nodeId)

    def test_environment(self):
        """
        The Open message includes the Environment loaded from an env variable.
        """
        connector = MDKConnector(env={"MDK_ENVIRONMENT": "myenv"})
        ws_actor = connector.expectSocket()
        open = connector.connect(ws_actor)
        assertEnvironmentEquals(self, open.environment, "myenv", None)
        connector = MDKConnector(env={"MDK_ENVIRONMENT": "parent:child"})
        ws_actor = connector.expectSocket()
        open = connector.connect(ws_actor)
        assertEnvironmentEquals(self, open.environment, "child", "parent")

    def test_default_environment(self):
        """
        The Environment is 'sandbox' if none env variable is set.
        """
        connector = MDKConnector()
        ws_actor = connector.expectSocket()
        open = connector.connect(ws_actor)
        assertEnvironmentEquals(self, open.environment, "sandbox", None)

    def test_close_no_error(self):
        """
        Receiving Close message with no error is handled without blowing up.
        """
        connector = MDKConnector()
        ws_actor = connector.expectSocket()
        connector.connect(ws_actor)
        ws_actor.send(Close().encode())
        connector.pump()

    def test_close_with_error(self):
        """
        Receiving a Close message with a ProtocolError logs the information in the error.
        """
        code = "300"
        detail = "MONKEYS EVERYWHERE AIIEEEEEEE"
        title = "Something bad happened"
        id = "specialsnowflake"
        close = Close()
        close.error = ProtocolError()
        close.error.code = code
        close.error.title = title
        close.error.detail = detail
        close.error.id = id
        connector = MDKConnector()
        ws_actor = connector.expectSocket()
        connector.connect(ws_actor)
        with self.assertLogs("quark.protocol", "INFO") as cm:
            ws_actor.send(close.encode())
            connector.pump()
        for text in [code, title, detail, id]:
            self.assertIn(text, cm.output[0])
        self.assertTrue(cm.output[0].startswith("ERROR"))


class InteractionReportingTests(TestCase):
    """The results of interactions are reported to the MCP."""

    def setUp(self):
        self.node1 = create_node("a1", "service1", environment="myenv")
        self.node2 = create_node("a2", "service2", environment="myenv")
        self.node3 = create_node("a3", "service3", environment="myenv")

    def add_nodes(self, mdk):
        """Register existence of nodes with the MDK instance."""
        mdk._disco.onMessage(None, NodeActive(self.node1))
        mdk._disco.onMessage(None, NodeActive(self.node2))
        mdk._disco.onMessage(None, NodeActive(self.node3))

    def test_interaction(self):
        """Interaction results are sent to the MCP."""
        connector = MDKConnector(env={"MDK_ENVIRONMENT": "myenv"})
        time_service = connector.runtime.getTimeService()
        ws_actor = connector.expectSocket()
        connector.connect(ws_actor)
        self.add_nodes(connector.mdk)

        session = connector.mdk.session()
        session.start_interaction()
        start_time = time_service.time()
        connector.advance_time(123)
        session.resolve("service1", "1.0")
        session.fail_interaction("fail")
        session.resolve("service2", "1.0")
        connector.advance_time(5)
        connector.pump()
        end_time = time_service.time()
        session.finish_interaction()
        connector.pump()
        connector.advance_time(5)
        connector.pump()

        # Skip log messages:
        ws_actor.swallowLogMessages()

        interaction = connector.expectInteraction(self, ws_actor, session,
                                                  [self.node1], [self.node2])
        self.assertEqual(interaction.startTimestamp, int(1000*start_time))
        self.assertEqual(interaction.endTimestamp, int(1000*end_time))
        self.assertEqual(interaction.environment.name, "myenv")


class LoggingTests(TestCase):
    """Tests for logging API of Session."""
    LEVELS = ["DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"]

    def assert_log_level_enforced(self, minimum_level):
        """Only log messages at or above the given level are sent."""
        mdk, tracer = create_mdk_with_faketracer()
        session = mdk.session()
        messages = ["a", "b", "c", "d", "e"]

        # Set logging level of the session:
        session.trace(minimum_level)
        # Log messages at all levels:
        for (l, m) in zip(self.LEVELS, messages):
            getattr(session, l.lower())("category", m)
        # Only messages at or above current level should actually be logged:
        result = [d["level"] for d in tracer.messages]
        expected_levels = self.LEVELS[self.LEVELS.index(minimum_level):]
        self.assertEqual(result, expected_levels)

    def test_log_levels_enforced(self):
        """
        Only log messages at or above the set trace level are sent onwards.
        """
        for level in self.LEVELS:
            self.assert_log_level_enforced(level)

    def test_log_result(self):
        """
        A LoggedMessageId matching the logged message is returned by logging APIs.
        """
        mdk, tracer = create_mdk_with_faketracer(environment="fallback:child")
        session = mdk.session()
        session.info("cat", "message")
        lmid = session.info("cat", "another message")
        logged = tracer.messages[1]
        self.assertEqual((lmid.traceId, lmid.causalLevel, lmid.environment,
                          lmid.environmentFallback),
                         (logged["context"], [2], "child", "fallback"))

    def test_log_result_too_low_level(self):
        """
        A LoggedMessageId matching the logged message is returned by logging APIs
        even when the given level is low enough that a message wasn't sent to
        the MCP.
        """
        mdk, tracer = create_mdk_with_faketracer()
        session = mdk.session()
        session.info("cat", "message")
        lmid = session.debug("cat", "another message")
        lmid2 = session.info("cat", "message")
        # Debug message wasn't set:
        self.assertEqual([d["level"] for d in tracer.messages],
                         ["INFO", "INFO"])
        # But we still got LoggedMessageId for debug message:
        self.assertEqual((lmid.causalLevel, lmid.traceId,
                          lmid2.causalLevel, lmid2.traceId),
                         ([2], session._context.traceId,
                          [3], session._context.traceId))

    def test_no_tracer(self):
        """
        If no tracer was setup, logging still returns a LoggedMessageId.
        """
        runtime = fakeRuntime()
        runtime.getEnvVarsService().set("MDK_DISCOVERY_SOURCE", "static:nodes={}")
        mdk = MDKImpl(runtime)
        mdk.start()
        # No DATAWIRE_TOKEN, so no tracer:
        self.assertEqual(mdk._tracer, None)
        session = mdk.session()
        session.info("cat", "message")
        lmid = session.info("cat", "another message")
        self.assertEqual((lmid.traceId, lmid.causalLevel),
                         (session._context.traceId, [2]))
