"""
Run tests written in Quark.
"""
from __future__ import print_function

import os
from glob import glob

import pytest

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUARK_TESTS_DIR = os.path.join(ROOT_DIR, "quark/tests")


# Tests that don't need to run on all languages:
@pytest.fixture(params=[filename for filename in glob(QUARK_TESTS_DIR + "/*.q")
                        if not filename.endswith("runtime_test.q")])
def filepath(request):
    return request.param


def test_run_python3_only(quark_run, filepath, websocket_echo_server):
    """Run Quark tests that don't need to run in multiple languages."""
    quark_run(filepath, "python3")


def test_run_all_languages(quark_run, quark_language, websocket_echo_server):
    """Run tests that have to be run in all languages."""
    quark_run(os.path.join(QUARK_TESTS_DIR, "runtime_test.q"), quark_language)
