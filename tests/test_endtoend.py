"""End-to-end tests for the MDK API."""

import os
import time
from random import random
from subprocess import Popen, check_output, check_call
from unittest import TestCase

CODE_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "source"))

os.putenv("MDK_DISCOVERY_URL", "wss://discovery-develop.datawire.io/ws/v1")
os.putenv("MDK_TRACING_URL", "wss://tracing-develop.datawire.io/ws")
os.putenv("MDK_TRACING_API_URL", "https://tracing-develop.datawire.io/api/logs")


def random_string():
    return "random_" + str(random())[2:]


class PythonTests(TestCase):
    """Tests for Python usage of MDK API."""

    def test_discovery(self):
        """Minimal discovery end-to-end test."""
        # 1. Services registered by one process can be looked up by another.
        service = random_string()
        address = random_string()
        p = Popen(["python", os.path.join(CODE_PATH, "register.py"), service, address])
        self.addCleanup(lambda: p.terminate())
        resolved_address = check_output(
            ["python", os.path.join(CODE_PATH, "resolve.py"), service])
        self.assertEqual(address, resolved_address)

        # 2. If the service is unregistered via MDK stop() then it is no longer resolvable.
        p.terminate()
        time.sleep(3)
        resolved_address = check_output(
            ["python", os.path.join(CODE_PATH, "resolve.py"), service])
        self.assertEqual("not found", resolved_address)

    def test_logging(self):
        """Minimal logging end-to-end test.

        Logs are written, and then same logs should be read back.
        """
        # Write some logs, waiting for them to arrive:
        service = random_string()
        check_call(["python", os.path.join(CODE_PATH, "write_logs.py"), service])

    def test_tracing(self):
        """Minimal tracing end-to-end test.

        One process can start a session context and a second one can join it,
        and they both get logged together.
        """
        context_id = check_output(
            ["python", os.path.join(CODE_PATH, "start_trace.py")])
        check_call(["python", os.path.join(CODE_PATH, "continue_trace.py"), context_id])
