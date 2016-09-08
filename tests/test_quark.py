"""
Run tests written in Quark.
"""
from __future__ import print_function

import os
from glob import glob
from subprocess import check_call
import pytest

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUARK_TESTS_DIR = os.path.join(ROOT_DIR, "quark/tests")
QUARK_VERSION = open(os.path.join(ROOT_DIR, "QUARK_VERSION.txt")).read().strip()
# Git tag starts with v, but the Docker tag does not:
if QUARK_VERSION.startswith("v"):
    QUARK_VERSION = QUARK_VERSION[1:]


# Tests that don't need to run on all languages:
@pytest.fixture(params=[filename for filename in glob(QUARK_TESTS_DIR + "/*.q")
                        if not filename.endswith("runtime_test.q")])
def filepath(request):
    return request.param

@pytest.fixture(params= ["python3", "python", "java", "ruby", "javascript"])
def language(request):
    return request.param


def test_run_python_only(filepath):
    """Run Quark tests that don't need to run in multiple languages."""
    run(filepath, "python")

def test_run_python3_only(filepath):
    """Run Quark tests that don't need to run in multiple languages."""
    run(filepath, "python3")


def test_run_all_languages(language):
    """Run tests that have to be run in all languages."""
    run(os.path.join(QUARK_TESTS_DIR, "runtime_test.q"), language)


def run(filepath, language):
    """Install and run a Quark test file."""
    docker_path = os.path.join("/code/quark/tests",
                               filepath[len(QUARK_TESTS_DIR) + 1:])
    print("Installing and running {} in {}...".format(filepath, language))
    check_call(["sudo", "docker", "run",
                # Mount volume into container so Docker can access quark files:
                "-v", ROOT_DIR + ":/code",] +
                ["datawire/quark-run:" + QUARK_VERSION, "--" + language, '--verbose', docker_path])
