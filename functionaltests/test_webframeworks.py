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
2. RecordingFailurePolicy used as the FailurePolicy.
3. An endpoint /resolve[?error=1]. Service "service1" should be resolved, and if
   error query flag is set an error should abort handling (e.g. raise an
   exception). Otherwise the result returned as a JSON object mapping resulting
   address to a list with first value being number of successes, second value
   being number of failures recorded.
4. A default timeout of 10 seconds.
5. An endpoint /timeout that returns the MDK session seconds to timeout as JSON.
"""

import pathlib
import sys
import os
from json import loads, dumps
from subprocess import Popen
from time import sleep

import requests
import pytest

from utils import run_python


WEBSERVERS_ROOT = pathlib.Path(__file__).parent / "webservers"


PORTS = [9190 + i for i in range(100)]


@pytest.fixture()
def port_number(worker_id):
    """A fixture that returns a different port for each parallel worker."""
    i = 0
    if worker_id != "master":
        i = int("".join([c for c in worker_id if c.isdigit()]))
    return PORTS[i]


@pytest.fixture(params=[
    # Flask, Python 3
    ["virtualenv3/bin/python", str(WEBSERVERS_ROOT / "flaskserver.py"), "$PORTNUMBER"],
    # Flask, Python 2
    ["virtualenv/bin/python", str(WEBSERVERS_ROOT / "flaskserver.py"), "$PORTNUMBER"],
    # Django 1.9, Python 3:
    ["virtualenv3/bin/python", str(WEBSERVERS_ROOT / "django-manage.py"),
     # Add --noreload so we don't have two Django processes,
     # which makes cleanup harder:
     "runserver", "$PORTNUMBER", "--noreload"],
    # Django 1.10, Python 2:
    ["virtualenv/bin/python", str(WEBSERVERS_ROOT / "django-manage.py"),
     "runserver", "$PORTNUMBER", "--noreload"],
    # Django 1.10, Python 3, with different middleware API:
    ["django110env/bin/python", str(WEBSERVERS_ROOT / "django110-manage.py"),
     "runserver", "$PORTNUMBER", "--noreload"],
    ["node", str(WEBSERVERS_ROOT / "expressserver.js"), "$PORTNUMBER"],
    ["ruby", str(WEBSERVERS_ROOT / "sinatraserver.rb"), "$PORTNUMBER"],
])
def webserver(request, port_number):
    """A fixture that runs a webserver in the background on port 9191."""
    # Tell MDK to hard code discovery source, and use testing-oriented failure
    # policy:
    env = os.environ.copy()
    env.update({"MDK_DISCOVERY_SOURCE":
                "static:nodes=" + dumps([
                    {"service": "service1", "address": "address1", "version": "1.0",
                     "id": "1234"},
                    {"service": "service2", "address": "address2", "version": "1.0",
                     "id": "5678"},
                ]),
                "MDK_FAILURE_POLICY": "recording"})
    command = [(str(port_number) if i == "$PORTNUMBER" else i)
               for i in request.param]
    p = Popen(command, env=env)
    # Wait for web server to come up:
    for i in range(10):
        try:
            requests.get(get_url(port_number, "/"), timeout=0.1)
        except:
            if p.poll() is not None:
                raise AssertionError("Webserver exited prematurely.")
            sleep(1.0)
        else:
            break
    yield
    p.terminate()
    p.wait()

def get_url(port, path):
    """Return the URL for a request."""
    return "http://localhost:%d%s" % (port, path)

def test_session_with_context(webserver, port_number):
    """
    If a X-MDK-CONTEXT header is sent to the webserver it reads it and uses the
    encoded session.
    """
    context = run_python(sys.executable, "create-context.py", output=True)
    returned_context = requests.get(get_url(port_number, "/context"),
                                    headers={"X-MDK-CONTEXT": context},
                                    timeout=5).json()
    assert loads(context.decode("utf-8"))["traceId"] == returned_context["traceId"]


def test_session_without_context(webserver, port_number):
    """
    If no X-MDK-CONTEXT header is sent to the webserver it creates a new
    session.
    """
    context = run_python(sys.executable, "create-context.py", output=True)
    returned_context = requests.get(get_url(port_number, "/context"), timeout=5).json()
    assert loads(context.decode("utf-8"))["traceId"] != returned_context["traceId"]


def test_interaction(webserver, port_number):
    """
    The webserver ties interactions to requests, and fails the interaction on
    errors.

    We test this by first sending a non-error request. The result should
    indicate no success for address1 because interaction ends *after* response
    is assembled.

    Then we send an erroring request.

    Then we send another non-error request. The result should indicate one
    success and single failure for address1.

    Then we send another non-error request. The result should indicate two
    successes and single failure for address1.
    """
    url = get_url(port_number, "/resolve")
    result1 = requests.get(url, timeout=5).json()
    assert result1 == {"address1": [0, 0]}
    assert requests.get(url + "?error=1").status_code in (500, 503)

    result2 = requests.get(url, timeout=5).json()
    # One success from first query, onse failure from second query:
    assert result2 == {"address1": [1, 1]}

    result3 = requests.get(url, timeout=5).json()
    # One success from first query, onse failure from second query, one success
    # from third query:
    assert result3 == {"address1": [2, 1]}


def test_timeout(webserver, port_number):
    """
    The web framework integration has a default MDK session that can be
    overriden by the timeout in the MDK context sent to it.
    """
    url = get_url(port_number, "/timeout")

    default = requests.get(url, timeout=5).json()
    assert abs(10 - default) < 2

    # Create a context with deadline of 5 seconds:
    context = run_python(sys.executable, "create-context.py", output=True)
    overriden = requests.get(url, headers={"X-MDK-CONTEXT": context},
                             timeout=5).json()
    assert abs(5 - overriden) < 2
