"""
Common utilities.
"""

from mdk_runtime import fakeRuntime
from mdk_discovery import CircuitBreakerFactory


def fake_runtime():
    """
    Create a fake runtime suitably configured for MDK usage.
    """
    runtime = fakeRuntime()
    runtime.dependencies.registerService(
            "failurepolicy_factory", CircuitBreakerFactory())
    return runtime

