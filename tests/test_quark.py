"""
Run tests written in Quark.
"""

import os
from glob import glob
from subprocess import check_call
from unittest import TestSuite, FunctionTestCase

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUARK_TESTS_DIR = os.path.join(ROOT_DIR, "quark/tests")
QUARK_VERSION = open(os.path.join(ROOT_DIR, "QUARK_VERSION.txt")).read().strip()
# Git tag starts with v, but the Docker tag does not:
if QUARK_VERSION.startswith("v"):
    QUARK_VERSION = QUARK_VERSION[1:]

def makeTest(filepath, language):
    """Create a test that installs and runs a Quark test file."""
    docker_path = os.path.join("/code/quark/tests",
                               filepath[len(QUARK_TESTS_DIR) + 1:])
    def testQuark():
        print("Installing and running {} in {}...".format(filepath, language))
        check_call(["sudo", "docker", "run",
                    "-v", ROOT_DIR + ":/code",
                    "datawire/quark-run:" + QUARK_VERSION, "--" + language, docker_path])
    return FunctionTestCase(testQuark, description="{}:{}".format(filepath, language))


def load_tests(*args, **kwargs):
    suite = TestSuite()
    tests = [makeTest(filename, language)
             for filename in glob(QUARK_TESTS_DIR + "/*.q")
             for language in ["python", "java", "ruby", "javascript"]]
    suite.addTests(tests)
    return suite
