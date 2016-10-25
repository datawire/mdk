from __future__ import print_function

import os
import sys
import time
from subprocess import check_call, check_output, Popen
import pytest

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
official = open(os.path.join(ROOT_DIR, "QUARK_VERSION.txt")).read().strip()
try:
    dirty = open(os.path.join(ROOT_DIR, "QUARK_VERSION-dirty.txt")).read().strip()
    QUARK_VERSION = dirty
    QUARK_VERSION_STATUS = "Overriding the quark version %s with the local quark version %s" % (official, dirty)
except IOError:
    QUARK_VERSION = official
    QUARK_VERSION_STATUS = "Testing with quark version %s, QUARK_VERSION-dirty.txt not found" % (official)
# Git tag starts with v, but the Docker tag does not:
if QUARK_VERSION.startswith("v"):
    QUARK_VERSION = QUARK_VERSION[1:]


def pytest_report_header(config):
    return QUARK_VERSION_STATUS


def maybe_sudo():
    if sys.platform == "darwin":
        return []
    else:
        return ["sudo"]


@pytest.fixture(scope="module")
def websocket_echo_server():
    """
    Launch a websocket echo server in a docker container so that other
    docker containers can connect to it easily (by name), even on MacOS.
    """
    # This command will fail during parallel execution, because
    # multiple containers cannot share the same name, but there is not
    # harm in that, as at least one server will be running.
    command = maybe_sudo() + "docker run --rm --name=websocket-echo datawire/websocket-echo".split()
    print(" ".join(command))
    Popen(command)
    # Wait for the container to have launched
    while True:
        dps_command = maybe_sudo() + "docker ps -f name=websocket-echo".split()
        print(" ".join(dps_command))
        dps_output = check_output(dps_command)
        print(dps_output)
        if b"websocket-echo" in dps_output:
            break
        time.sleep(0.25)


def run(filepath, language):
    """Install and run a Quark test file."""
    docker_path = os.path.join("/code",
                               filepath[len(ROOT_DIR) + 1:])
    print("Installing and running {} in {}...".format(filepath, language))
    command = (maybe_sudo() +
               ["docker", "run", "--rm",
                # Mount volume into container so Docker can access quark files:
                "-v", ROOT_DIR + ":/code",
                # Link to local websocket echo server running in another container
                "--link", "websocket-echo",
               ] +
               ["datawire/quark-run:" + QUARK_VERSION, "--" + language, '--verbose', docker_path])
    print(" ".join(command))
    check_call(command)

@pytest.fixture
def quark_run(request):
    return run

@pytest.fixture(params= ["python3", "python", "java", "ruby", "javascript"])
def quark_language(request):
    return request.param
