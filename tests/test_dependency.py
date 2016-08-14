"""
Tests for dependency.q.
"""

from __future__ import absolute_import

from unittest import TestCase

from dependency import Dependencies


class DependencyTests(TestCase):
    """
    Tests for Dependencies.
    """
    def test_registerAndGet(self):
        """
        It's possible to register and then retrieves services.
        """
        a, b = object(), object()
        deps = Dependencies()
        deps.registerService("A", a)
        deps.registerService("B", b)
        self.assertEqual(
            (a, b),
            (deps.getService("A"), deps.getService("B")))

    def test_hasService(self):
        """
        It's possible to check whether a service exists.
        """
        deps = Dependencies()
        deps.registerService("A", object())
        self.assertEqual(
            (True, False),
            (deps.hasService("A"), deps.hasService("B")))

