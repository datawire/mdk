"""
Django middleware that enables the MDK.

This is old-style (Django <1.10) middleware. Please see
https://docs.djangoproject.com/en/1.10/topics/http/middleware/#upgrading-middleware
if you're using Django 1.10.
"""

import atexit
from traceback import format_exception_only

from mdk import start


class MDKSessionMiddleware(object):
    """
    Add an MDK session to the Django request, as well as circuit breaker
    support.

    The request object will get a ``mdk_session`` attribute added to it.
    """
    def __init__(self):
        self.mdk = start()
        atexit.register(self.mdk.stop)

    def process_request(self, request):
        request.mdk_session = self.mdk.join(
            request.META.get("HTTP_X_MDK_CONTEXT"))
        request.mdk_session.start_interaction()

    def process_response(self, request, response):
        request.mdk_session.finish_interaction()
        del request.mdk_session
        return response

    def process_exception(self, request, exception):
        request.mdk_session.fail_interaction(
            "".join(format_exception_only(exception.__class__, exception)))
