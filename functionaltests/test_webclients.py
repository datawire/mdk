"""
Functional tests for web client MDK integration.

Web clients should:

1. Initialize a MDK session and set a timeout of 1.0 seconds on the session.
2. Do a GET on the URL given on the command line and write the resulting body to
   stdout.
3. Exit with exit code 123 if the request times out.
"""

import os
import pathlib
from subprocess import check_call, CalledProcessError

from twisted.web.resource import Resource
from twisted.web.server import Site, NOT_DONE_YET
from twisted.internet import reactor

from mdk_protocol import SharedContext


from crochet import setup, wait_for
setup()

import pytest


WEBCLIENTS_ROOT = pathlib.Path(__file__).parent / "webclients"

TIMEOUT_CODE = 123


class ServerResource(Resource):
    isLeaf = True

    def __init__(self, received):
        self.received = received
        Resource.__init__(self)

    def render(self, request):
        delay = float(request.args.get(b"delay", [0])[0])
        self.received.append(
            request.requestHeaders.getRawHeaders(b"X-MDK-CONTEXT")[0])
        def done():
            request.setHeader('content-length', '3')
            request.write(b'abc')
            request.finish()
        reactor.callLater(delay, done)
        return NOT_DONE_YET


@wait_for(timeout=1.0)
def start_server():
    received = []
    port = reactor.listenTCP(0, Site(ServerResource(received)))

    @wait_for(timeout=1.0)
    def stop():
        return port.stopListening()
    return port.getHost().port, received, stop


@pytest.fixture()
def webserver():
    port_number, received, stop = start_server()
    try:
        yield "http://localhost:{}/".format(port_number), received
    finally:
        stop()

@pytest.fixture(params=[
    # Python 3:
    ["virtualenv3/bin/python", str(WEBCLIENTS_ROOT / "requeststest.py")],
    # Python 2:
    ["virtualenv/bin/python", str(WEBCLIENTS_ROOT / "requeststest.py")],
    ["ruby", str(WEBCLIENTS_ROOT / "faraday.rb")],
    ["node", str(WEBCLIENTS_ROOT / "request.js")],
])
def webclient(request):
    env = os.environ.copy()
    env.update({"MDK_DISCOVERY_SOURCE": "static:nodes={}"})
    def client(url):
        return check_call(request.param + [url], env=env)
    return client


def test_timeout(webserver, webclient):
    """The client enforces a timeout."""
    url, received = webserver
    # The client should have timeout of 1 seconds, we set delay in responding of
    # 10:
    try:
        webclient(url + "?delay=10")
    except CalledProcessError as e:
        assert e.returncode == TIMEOUT_CODE
    else:
        assert False # didn't get timeout error

def test_context_header(webserver, webclient):
    """The client sends a X-MDK-CONTEXT header to the server."""
    url, received = webserver
    webclient(url)
    result = SharedContext.decode(str(received[0], "utf-8"))
    # We got MDK context in the X-MDK-CONTEXT header:
    assert isinstance(result, SharedContext)
