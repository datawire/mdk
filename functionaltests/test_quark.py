"""
Run tests written in Quark.
"""
from __future__ import print_function

import os
from glob import glob

import crochet
crochet.setup()

from autobahn.twisted.websocket import (
    WebSocketServerProtocol, WebSocketServerFactory)
from twisted.internet import reactor
from twisted.internet.error import CannotListenError
import pytest

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUARK_TESTS_DIR = os.path.join(ROOT_DIR, "quark/tests")


class Echo(WebSocketServerProtocol):
    """Echo messages."""
    def onMessage(self, payload, isBinary):
        self.sendMessage(payload, isBinary)

@crochet.wait_for(timeout=1.0)
def websocket_echo_server():
    factory = WebSocketServerFactory()
    factory.protocol = Echo
    try:
        reactor.listenTCP(9123, factory)
    except CannotListenError:
        print("Couldn't listen on port 9123; if you're running in "
              "parallel py.test mode you'll see a few of these.")
        pass
websocket_echo_server()


# Tests that don't need to run on all languages:
@pytest.fixture(params=[filename for filename in glob(QUARK_TESTS_DIR + "/*.q")
                        if not filename.endswith("runtime_test.q")])
def filepath(request):
    return request.param


def test_run_python_only(quark_run, filepath):
    """Run Quark tests that don't need to run in multiple languages."""
    quark_run(filepath, "python")

def test_run_python3_only(quark_run, filepath):
    """Run Quark tests that don't need to run in multiple languages."""
    quark_run(filepath, "python3")


def test_run_all_languages(quark_run, quark_language):
    """Run tests that have to be run in all languages."""
    quark_run(os.path.join(QUARK_TESTS_DIR, "runtime_test.q"), quark_language)

