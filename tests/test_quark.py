"""
Run tests written in Quark.
"""

import os
from glob import glob
from subprocess import check_call
from unittest import TestSuite, FunctionTestCase

ROOT_DIR = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "../quark/tests"))

def makeTest(filepath, language):
    """Create a test that installs and runs a Quark test file."""
    def testQuark():
        print("Installing {} in {}...".format(filepath, language))
        check_call(["quark", "install", "--" + language, filepath])
        print("Running {} in {}...".format(filepath, language))
        check_call(["quark", "run", "--" + language, filepath])
    return FunctionTestCase(testQuark, description="{}:{}".format(filepath, language))


def load_tests(*args, **kwargs):
    suite = TestSuite()
    tests = [makeTest(os.path.join(ROOT_DIR, filename), language)
             for filename in glob(ROOT_DIR + "/*.q")
             for language in ["python", "java", "ruby", "javascript"]]
    suite.addTests(tests)
    return suite
