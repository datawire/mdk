"""End-to-end tests for the MDK API."""

import os
import time
from random import random
from subprocess import Popen, check_output
from unittest import TestCase

CODE_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "source"))

DISCOVERY_URL = "wss://discovery-develop.datawire.io/"

os.putenv("MDK_DISCOVERY_URL", DISCOVERY_URL)


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

    # Test logging.