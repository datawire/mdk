"""End-to-end tests for the MDK API."""
from builtins import str

import os
import sys
import time
from random import random
from subprocess import Popen, check_call, check_output
from unittest import TestCase

from utils import CODE_PATH, run_python

def random_string():
    return "random_" + str(random())[2:]


def assertRegisteryDiscoverable(test, discover):
    """
    Services registered by one process can be looked up by another.

    :param test: A TestCase instance.
    :param discover: a callable that takes the service name and returns the
    resolved address.

    Returns the registeration Popen object and the service.
    """
    service = random_string()
    address = random_string()
    p = Popen([sys.executable, os.path.join(CODE_PATH, "register.py"), service, address])
    test.addCleanup(lambda: p.kill())
    resolved_address = discover(service).decode("utf-8")
    test.assertIn(address, resolved_address)
    return p, service


class PythonTests(TestCase):
    """Tests for Python usage of MDK API."""

    def test_discovery(self):
        """Minimal discovery end-to-end test."""
        # 1. Services registered by one process can be looked up by another.
        p, service = assertRegisteryDiscoverable(
            self,
            lambda service: run_python("resolve.py", [service], output=True))

        # 2. If the service is unregistered via MDK stop() then it is no longer resolvable.
        p.terminate()
        time.sleep(3)
        resolved_address = run_python("resolve.py", [service], output=True)
        self.assertEqual(b"not found", resolved_address)

    def test_logging(self):
        """Minimal logging end-to-end test.

        Logs are written, and then same logs should be read back.
        """
        # Write some logs, waiting for them to arrive:
        service = random_string()
        run_python("write_logs.py", [service])

    def test_tracing(self):
        """Minimal tracing end-to-end test.

        One process can start a session context and a second one can join it,
        and they both get logged together.
        """
        context_id = run_python("start_trace.py", output=True)
        print("context_id", context_id)
        run_python("continue_trace.py", [context_id])


class JavascriptTests(TestCase):
    """Tests for Javascript usage of MDK."""

    def test_logging(self):
        """Logs are written, and then the same logs should be read back."""
        check_call(["node", os.path.join(CODE_PATH, "write_logs.js"),
                    random_string()])

    def test_discovery(self):
        """Minimal discovery end-to-end test with a Javascript client."""
        assertRegisteryDiscoverable(
            self,
            lambda service: check_output(
                ["node", os.path.join(CODE_PATH, "resolve.js"), service]))


class RubyTests(TestCase):
    """Tests for Ruby usage of MDK."""

    def test_logging(self):
        """Logs are written, and then the same logs should be read back."""
        check_call(["ruby", os.path.join(CODE_PATH, "write_logs.rb"),
                    random_string()])

    def test_discovery(self):
        """Minimal discovery end-to-end test with a Javascript client."""
        assertRegisteryDiscoverable(
            self,
            lambda service: check_output(
                ["ruby", os.path.join(CODE_PATH, "resolve.rb"), service]))


class JavaTests(TestCase):
    """Tests for Java usage of MDK."""

    def test_logging(self):
        """Logs are written, and then the same logs should be read back."""
        check_call(["mvn", "-f", os.path.join(CODE_PATH, "writelogs_java/pom.xml"),
                    "package"])
        check_call(
            ["java", "-jar", os.path.join(CODE_PATH,
                                          "writelogs_java/target/writelogs-0.0.1.jar"),
             random_string()])

    def test_discovery(self):
        """Minimal discovery end-to-end test with a Javascript client."""
        check_call(["mvn", "-f", os.path.join(CODE_PATH, "resolve_java/pom.xml"),
                    "package"])
        assertRegisteryDiscoverable(
            self,
            lambda service: check_output(
                ["java", "-jar", os.path.join(
                    CODE_PATH,"resolve_java/target/resolve-0.0.1.jar"),
                 service]))
