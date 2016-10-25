"""
Flask integration for the MDK.

This requires Flask and the blinker library.
"""

from __future__ import absolute_import

import atexit
import traceback

from mdk import start
from .logging import MDKHandler

from flask import (
    g, request, request_started, got_request_exception, request_tearing_down,
)


def _on_request_started(sender, **extra):
    """Create a new MDK session at request start."""
    g.mdk_session = sender.mdk.join(
        request.headers.get(sender.mdk.CONTEXT_HEADER))
    g.mdk_session.start_interaction()

def _on_request_exception(sender, **extra):
    """Fail interaction when a request handlers raises an error."""
    exc = extra.get("exception", None)
    g.mdk_session.fail_interaction(
        "".join(traceback.format_exception_only(exc.__class__, exc)))

def _on_request_tearing_down(sender, **extra):
    """Finish an interaction when a request is done."""
    g.mdk_session.finish_interaction()
    del g.mdk_session


def mdk_setup(app, timeout=None, mdk=None):
    """
    Setup MDK integration with Flask.

    :param app: A Flask application instance.
    :param timeout: Default timeout in seconds to set for the MDK session.
    :param mdk: An optional ``mdk.MDK`` instance to use instead of creating a
        new one. It will not be started or stopped.

    :return: The ``mdk.MDK`` instance.
    """
    if mdk is None:
        app.mdk = start()
        atexit.register(app.mdk.stop)
    else:
        app.mdk = mdk
    if timeout is not None:
        app.mdk.setDefaultDeadline(timeout)
    request_started.connect(_on_request_started, app)
    got_request_exception.connect(_on_request_exception, app)
    request_tearing_down.connect(_on_request_tearing_down, app)
    return app.mdk


class MDKLoggingHandler(MDKHandler):
    """
    ``logging.Handler`` that routes logs to MDK and extracts MDK session from
    the Flask request.
    """
    def __init__(self, mdk):
        """
        :param mdk: A ``mdk.MDK`` instance.
        """
        def get_session():
            if not g:
                return None
            return getattr(g, "mdk_session", None)
        MDKHandler.__init__(self, mdk, get_session)


__all__ = ["mdk_setup", "MDKLoggingHandler"]
