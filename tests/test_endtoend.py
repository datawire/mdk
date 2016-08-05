"""End-to-end tests for the MDK API."""

import os
import time
from random import random
from subprocess import Popen, check_output, check_call
from unittest import TestCase

CODE_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "source"))


def random_string():
    return "random_" + str(random())[2:]


def run_python(command, extra_args=(), output=False):
    """
    Run a Python program.

    Returns output if output=True, in which case stderr will cause error.
    """
    args = ["python", os.path.join(CODE_PATH, command)] + list(extra_args)
    if output:
        command = check_output
    else:
        command = check_call
    return command(args)


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
    p = Popen(["python", os.path.join(CODE_PATH, "register.py"), service, address])
    test.addCleanup(lambda: p.terminate())
    resolved_address = discover(service)
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
        self.assertEqual("not found", resolved_address)

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
