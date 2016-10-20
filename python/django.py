"""
Django middleware that enables the MDK.
"""

import atexit
from traceback import format_exception_only

from django.conf import settings
from django.apps import AppConfig, apps

from mdk import start

# Django 1.10 new-style middleware compatibility:
try:
    from django.utils.deprecation import MiddlewareMixin
except ImportError:
    MiddlewareMixin = object


__all__ = ["MDKSessionMiddleware", "MDKAppConfig"]


class MDKSessionMiddleware(MiddlewareMixin):
    """
    Add an MDK session to the Django request, as well as circuit breaker
    support.

    The request object will get a ``mdk_session`` attribute added to it.

    Set a MDK_DEFAULT_TIMEOUT variable to a number of seconds in ``settings.py``
    if you want timeouts.
    """
    def process_request(self, request):
        request.mdk_session = apps.get_app_config("datawire_mdk").mdk.join(
            request.META.get("HTTP_X_MDK_CONTEXT"))
        request.mdk_session.start_interaction()

    def process_response(self, request, response):
        request.mdk_session.finish_interaction()
        del request.mdk_session
        return response

    def process_exception(self, request, exception):
        request.mdk_session.fail_interaction(
            "".join(format_exception_only(exception.__class__, exception)))


class MDKAppConfig(AppConfig):
    """Configure MDK in general for a Django application.

    Don't override the name or label in subclasses.
    """
    name = "mdk.django"
    label = "datawire_mdk"

    def ready(self):
        self.mdk = start()
        timeout = getattr(settings, "MDK_DEFAULT_TIMEOUT", None)
        if timeout is not None:
            self.mdk.setDefaultDeadline(timeout)
        atexit.register(self.mdk.stop)
        self.mdk_ready(self.mdk)

    def mdk_ready(self, mdk):
        """Override in subclasses to set MDK settings."""
