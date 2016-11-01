"""End-to-end tests for the MDK API."""
from builtins import str

import os
import sys
import time
from random import random
from subprocess import Popen, check_call, check_output
from unittest import TestCase
from json import dumps

from utils import CODE_PATH, ROOT_PATH, run_python

def random_string():
    return "random_" + str(random())[2:]


def assertRegisteryDiscoverable(test, discover, additional_env={}):
    """
    Services registered by one process can be looked up by another.

    :param test: A TestCase instance.
    :param discover: a callable that takes the service name and returns the
    resolved address.
    :param additional_env: Additional environment variables to set.

    Returns the registeration Popen object and the service.
    """
    service = random_string()
    address = random_string()
    env = os.environ.copy()
    env.update(additional_env)
    p = Popen([sys.executable, os.path.join(CODE_PATH, "register.py"),
               service, address], env=env)
    test.addCleanup(lambda: p.kill())
    resolved_address = discover(service).decode("utf-8")
    test.assertIn(address, resolved_address)
    return p, service, address


def assertNotResolvable(test, service, additional_env={}):
    """Assert the service isn't resolvable."""
    env = os.environ.copy()
    env.update(additional_env)
    resolved_address = run_python(sys.executable, "resolve.py",
                                  [service], output=True, env=env)
    test.assertEqual(b"not found", resolved_address)


class Python2Tests(TestCase):
    """Tests for Python usage of MDK API."""

    python_binary = os.path.join(ROOT_PATH, "virtualenv/bin/python")

    def test_discovery(self):
        """Minimal discovery end-to-end test."""
        # 1. Services registered by one process can be looked up by another.
        p, service, _ = assertRegisteryDiscoverable(
            self,
            lambda service: run_python(self.python_binary, "resolve.py",
                                       [service], output=True))

        # 2. If the service is unregistered via MDK stop() then it is no longer resolvable.
        p.terminate()
        time.sleep(3)
        assertNotResolvable(self, service)

    def test_logging(self):
        """Minimal logging end-to-end test.

        Logs are written, and then same logs should be read back.
        """
        # Write some logs, waiting for them to arrive:
        service = random_string()
        run_python(self.python_binary, "write_logs.py", [service])

    def test_tracing(self):
        """Minimal tracing end-to-end test.

        One process can start a session context and a second one can join it,
        and they both get logged together.
        """
        context_id = run_python(self.python_binary, "create_trace.py", output=True)
        expected_messages = dumps([("process1", "hello"), ("process2", "world")])
        p = Popen([sys.executable, os.path.join(CODE_PATH, "read_logs.py"),
                   context_id, expected_messages])
        print("context_id", context_id)
        # Ensure the subscription is in place before we send messages:
        time.sleep(8)
        context_id = run_python(self.python_binary, "start_trace.py", [context_id], output=True)
        run_python(self.python_binary, "continue_trace.py", [context_id])
        assert p.wait() == 0


class Python3Tests(Python2Tests):
    """Tests for Python 3 usage of MDK API."""

    python_binary = os.path.join(ROOT_PATH, "virtualenv3/bin/python")

    def test_defaultEnvironmentIsolation(self):
        """
        A service registered in default environment can't be resolved from another
        environment.
        """
        # 1. Register in default environment
        _, service, _ = assertRegisteryDiscoverable(
            self,
            lambda service: run_python(self.python_binary, "resolve.py",
                                       [service], output=True,
                                       additional_env={
                                           "MDK_ENVIRONMENT": "sandbox"}))
        # 2. Assert it can't be found in a different environment:
        assertNotResolvable(self, service, {"MDK_ENVIRONMENT": "anotherenv"})

    def assertResolvable(self, service, environment, expected_address,
                         context=None):
        """
        Assert a service can be resolved in the given environment.
        """
        params = [service]
        if context is not None:
            params.append(context)
        address = run_python(self.python_binary, "resolve.py",
                             params, output=True,
                             additional_env={"MDK_ENVIRONMENT": environment})
        self.assertEqual(address.decode("utf-8"), expected_address)

    def registerInAnEnvironment(self, environment):
        """
        Register a service in the specified environment.
        """
        env = {"MDK_ENVIRONMENT": environment}
        _, service, address = assertRegisteryDiscoverable(
            self,
            lambda service: run_python(self.python_binary, "resolve.py",
                                       [service], output=True,
                                       additional_env=env),
            additional_env=env)
        return service, address

    def test_environmentIsolation(self):
        """
        A service registered in environment A can't be resolved from another
        environment.
        """
        # 1. Register in one environment
        service, _ = self.registerInAnEnvironment("firstenv")
        # 2. Assert it can't be found in a different environment:
        assertNotResolvable(self, service, {"MDK_ENVIRONMENT": "anotherenv"})

    def test_environmentFallback(self):
        """
        Imagine an environment 'parent:child'.

        Service A that is in environment 'parent:child' can communicate with a
        service B that is in enviornment 'parent'.

        Furthermore, the session preserves the original environment, so if A
        calls B and B wants to call C within the same session, if C is in
        'parent:child' it will be found by B.
        """
        # 1. Create a session in environment parent:child
        context_id = run_python(self.python_binary, "create_trace.py", output=True,
                                additional_env={"MDK_ENVIRONMENT": "parent:child"})
        # 2. Register B in parent, and C in parent:child
        serviceB, addressB = self.registerInAnEnvironment("parent")
        serviceC, addressC = self.registerInAnEnvironment("parent:child")
        # 3. Services in parent:child can resolve B, even though it's in
        # parent, both with and without a parent:child session:
        self.assertResolvable(serviceB, "parent:child", addressB)
        self.assertResolvable(serviceB, "parent:child", addressB, context_id)
        # 4. Services in parent can resolve C if it's joined a parent:child
        # session, but not with its normal sessions:
        self.assertResolvable(serviceC, "parent:child", addressC, context_id)
        assertNotResolvable(self, serviceC, {"MDK_ENVIRONMENT": "parent"})

    def test_environmentWithFallbackIdentity(self):
        """
        The environment variable 'parent:child' creates the same environment as
        'child', so services configured either way can see each other.
        """
        # 1. Register B in parent:child, and C in child
        serviceB, addressB = self.registerInAnEnvironment("child")
        serviceC, addressC = self.registerInAnEnvironment("parent:child")
        # 2. parent:child can see anything in child, and vice versa
        # parent, both with and without a parent:child session:
        self.assertResolvable(serviceB, "parent:child", addressB)
        self.assertResolvable(serviceC, "child", addressC)


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
        """Minimal discovery end-to-end test with a Ruby client."""
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
        """Minimal discovery end-to-end test with a Java client."""
        check_call(["mvn", "-f", os.path.join(CODE_PATH, "resolve_java/pom.xml"),
                    "package"])
        assertRegisteryDiscoverable(
            self,
            lambda service: check_output(
                ["java", "-jar", os.path.join(
                    CODE_PATH,"resolve_java/target/resolve-0.0.1.jar"),
                 service]))
