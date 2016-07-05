"""End-to-end tests for the MDK API."""

import os
from signal import SIGTERM
from random import random
from subprocess import Popen, check_output, STDOUT
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
        """Services registered by one process can be looked up by another."""
        service = random_string()
        address = random_string()
        p = Popen(["python", os.path.join(CODE_PATH, "register.py"), service, address])
        self.addCleanup(lambda: os.kill(p.pid, SIGTERM))
        resolved_address = check_output(
            ["python", os.path.join(CODE_PATH, "resolve.py"), service])
        self.assertEqual(address, resolved_address)

    # Services registered by stop()ed MDK are no longer resolvable

    # Something something logging.
