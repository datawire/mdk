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
    args = ["python", os.path.join("register.py")] + list(extra_args)
    if output:
        command = check_output
    else:
        command = check_call
    return command(args)


class PythonTests(TestCase):
    """Tests for Python usage of MDK API."""

    def assertRegisteryDiscoverable(self, discover):
        """
        Services registered by one process can be looked up by another.

        discover is a callable that takes the service name and returns the
        resolved address.

        Returns the registeration Popen object and the service.
        """
        service = random_string()
        address = random_string()
        p = Popen(["python", os.path.join(CODE_PATH, "register.py"), service, address])
        self.addCleanup(lambda: p.terminate())
        resolved_address = discover(service)
        self.assertIn(address, resolved_address)
        return p, service

    def test_discovery(self):
        """Minimal discovery end-to-end test."""
        # 1. Services registered by one process can be looked up by another.
        p, service = self.assertRegisteryDiscoverable(
            lambda service: run_python("resolve.py", [service], output=True))

        # 2. If the service is unregistered via MDK stop() then it is no longer resolvable.
        p.terminate()
        time.sleep(3)
        resolved_address = run_python("resolve.py", [service], output=True)
        self.assertEqual("not found", resolved_address)

    def test_discovery_js(self):
        """Minimal discovery end-to-end test with a Javascript client."""
        self.assertRegisteryDiscoverable(
            lambda service: check_output(
                ["node", os.path.join(CODE_PATH, "resolve.js"), service]))

    def test_logging_py(self):
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
