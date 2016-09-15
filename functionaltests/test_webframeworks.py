"""
Web framework integration tests.

We want to verify:
1. Request start interaction
2. Response ends interaction
3. X-MDK-CONTEXT is parsed, new session created otherwise
4. errors cause interaction failure

To test a web framework you must create a server using that has the following
setup:

1. An endpoint /context that returns the result of externalize() on the current
   session. This verifies X-MDK-CONTEXT handling.
2. StaticRoutes used as a discovery source with nodes service1 -> address1,
   service2 -> address2, service2 -> service3.
3. RecordingFailurePolicy used as the FailurePolicy.
4. An endpoint /resolve?services=a,b,c. Each comma separated service should be
   resolved, and the result returned as a JSON object mapping service name to a
   list with first value being number of successes, second value being number of
   failures recorded.


XXXX
Implementation ideas:

For errors:
1. Add a FailurePolicy that records failures
2. Test suite registers known bad service with unique id that is at localhost:1, thus causing failures if connected to? or maybe just hard code a particular address as being bad and causing exception?

For X-MDK-Context:
Send query with header that causes logging.
Send query without header that causes logging.

For interaction start:
Add StaticDiscoverySource that stores entries in memory.
Add API for extracting nodes used in an interaction?
"""

import pathlib
import sys
from json import loads
from subprocess import Popen

import requests
import pytest

from utils import run_python


WEBSERVERS_ROOT = pathlib.Path(__file__).parent / "webservers"
URL = "http://localhost:9191"


@pytest.fixture(scope="module",
                params=[
                    [sys.executable, str(WEBSERVERS_ROOT / "flaskserver.py")],
                ])
def webserver(request):
    """A fixture that runs a webserver in the background on port 9191."""
    p = Popen(request.param)
    yield
    p.terminate()
    p.wait()


def test_with_context(webserver):
    """
    If a X-MDK-CONTEXT header is sent to the webserver it reads it and uses the
    encoded session.
    """
    context = run_python("create-context.py", output=True)
    returned_context = requests.get(URL + "/context",
                                    headers={"X-MDK-CONTEXT": context}).json()
    assert loads(context.decode("utf-8"))["traceId"] == returned_context["traceId"]


def test_without_context(webserver):
    """
    If no X-MDK-CONTEXT header is sent to the webserver it creates a new
    session.
    """
    context = run_python("create-context.py", output=True)
    returned_context = requests.get(URL + "/context").json()
    assert loads(context.decode("utf-8"))["traceId"] != returned_context["traceId"]
