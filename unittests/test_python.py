"""
Unit tests for Python-specific code.
"""

import logging
from unittest import TestCase

from flask import Flask, g

from mdk_tracing import FakeTracer
from mdk_runtime import fakeRuntime
from mdk import MDKImpl
from mdk.logging import MDKHandler
from mdk.flask import MDKLoggingHandler, mdk_setup


def create_mdk():
    """Create an MDK with a FakeTracer.

    Returns (mdk, fake_tracer).
    """
    runtime = fakeRuntime()
    tracer = FakeTracer()
    runtime.dependencies.registerService("tracer", tracer)
    runtime.getEnvVarsService().set("MDK_DISCOVERY_SOURCE", "static:nodes={}")
    mdk = MDKImpl(runtime)
    mdk.start()
    return mdk, tracer


class LoggingTests(TestCase):
    """Tests for stdlib-logging integration."""

    def test_logPassthrough(self):
        """If MDKHandler is used, logging via stdlib is passed to MDK."""
        logger = logging.Logger("mylog")
        logger.setLevel(logging.DEBUG)
        mdk, tracer = create_mdk()
        session = mdk.session()
        session.trace("DEBUG")
        logger.addHandler(MDKHandler(mdk, lambda: session))

        logger.debug("debugz")
        logger.info("infoz")
        logger.warning("warnz")
        logger.error("errorz")
        logger.critical("criticalz")

        self.assertEqual(
            tracer.messages,
            [{"level": level.upper(), "category": "mylog",
              "text": level + "z", "context": session._context.traceId}
             for level in ["debug", "info", "warn", "error", "critical"]])

    def test_format(self):
        """MDKHandler uses Python stdlib formatting."""
        logger = logging.Logger("mylog")
        mdk, tracer = create_mdk()
        session = mdk.session()
        logger.addHandler(MDKHandler(mdk, lambda: session))

        logger.info("hello %s", "world")
        self.assertEqual(tracer.messages[0]["text"], "hello world")

    def test_noInfiniteLoops(self):
        """
        Sometimes MDK logging results in native, i.e. Python logging. Ensure this
        doesn't cause infinite loop when we route Python logging to MDK.
        """
        mdk, tracer = create_mdk()
        # Make logging into MDK log back into Python logging:
        tracer.log = lambda *args, **kwargs: logging.info("hello!")
        handler = MDKHandler(mdk, lambda: mdk.session())

        root_logger = logging.getLogger()
        root_logger.addHandler(handler)
        self.addCleanup(lambda: root_logger.removeHandler(handler))
        logging.error("zoop")

    def test_sessions(self):
        """
        The given session's context is used; if no session is available a default
        session is used.
        """
        mdk, tracer = create_mdk()
        session1, session3 = mdk.session(), mdk.session()
        def get_session(results=[session1, None, session3]):
            return results.pop(0)

        logger = logging.Logger("mylog")
        handler = MDKHandler(mdk, get_session)
        logger.addHandler(handler)
        for i in range(3):
            logger.info("hello")
        self.assertEqual([d["context"] for d in tracer.messages],
                         [s._context.traceId for s in
                          [session1, handler._default_session, session3]])


def make_flask_app(logger):
    """Create a Flask app that logs to the given Logger."""
    app = Flask("myapp")

    @app.route("/")
    def log():
        logger.info("hello: " + g.mdk_session._context.traceId)
        return ""

    return app


class FlaskLoggingTests(TestCase):
    """Test for Flask's logging integration."""

    def tes_withinARequest(self):
        """
        When logging inside a Flask route, the MDK Session for the request is used
        if MDKLoggingHandler was set up.
        """
        logger = logging.Logger("logz")
        mdk, tracer = create_mdk()
        app = make_flask_app(logger)
        mdk_setup(app, mdk=mdk)

        handler = MDKLoggingHandler(mdk)
        logger.addHandler(handler)
        client = app.test_client()
        client.get("/")
        message = tracer.messages[-1]
        self.assertEqual("hello: " + message["context"], message["text"])

    def test_outsideARequest(self):
        """
        When logging outside a Flask route, MDKLoggingHandler still ensures logs are
        passed to MDK.
        """
        logger = logging.Logger("logz")
        mdk, tracer = create_mdk()

        handler = MDKLoggingHandler(mdk)
        logger.addHandler(handler)
        logger.info("helloz!")
        message = tracer.messages[-1]
        self.assertEqual("helloz!", message["text"])
