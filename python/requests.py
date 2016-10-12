"""
Requests HTTP library (http://requests.readthedocs.io/) integration for the
MDK.
"""

from sys import maxsize

from mdk import MDK

from requests import Session
from requests.adapters import HTTPAdapter

__all__ = ["requests_session"]


def requests_session(mdk_session):
    """
    Create a ``requests.Session`` from an MDK session.

    The resulting ``requests.Sesssion`` will:

    1. Set timeouts based on the timeout set on the MDK session.
    2. Send the X-MDK-CONTEXT HTTP header in all HTTP requests.

    IMPORTANT: Because of item #2 the resulting ``requests.Sesssion`` should
    only be used to talk to systems that use the MDK; the X-MDK-CONTEXT header
    may leak information about your system's internals.

    The resulting ``requests.Session`` has an adapter set. If you want to add
    your own additional adapters you will need to use something like
    https://pypi.python.org/pypi/requests-middleware.
    """
    req_session = Session()
    adapter = _MDKAdapter(mdk_session)
    req_session.mount("http://", adapter)
    req_session.mount("https://", adapter)
    return req_session


class _MDKAdapter(HTTPAdapter):
    """
    Set timeouts and session context header from the MDK session.

    See
    http://requests.readthedocs.io/en/master/api/#requests.adapters.HTTPAdapter
    for details.
    """
    def __init__(self, mdk_session):
        self._mdk_session = mdk_session
        HTTPAdapter.__init__(self)

    def add_headers(self, request, **kwargs):
        """Override base class."""
        headers = (request.headers or {}).copy()
        headers[MDK.CONTEXT_HEADER] = self._mdk_session.externalize()
        request.headers = headers

    def _get_timeout(self, proposed_timeout):
        """
        Given a proposed timeout, return a timeout that takes the MDK session
        timeout into account.
        """
        mdk_timeout = self._mdk_session.getRemainingTime()
        if mdk_timeout is None:
            mdk_timeout = maxsize
        if proposed_timeout is None:
            proposed_timeout = maxsize
        result = min(mdk_timeout, proposed_timeout)
        if result == maxsize:
            result = None
        return result

    def send(self, request, stream=False, timeout=None, verify=True, cert=None,
             proxies=None):
        """Override base class."""
        if isinstance(timeout, tuple):
            connect_timeout, read_timeout = timeout
            timeout = (self._get_timeout(connect_timeout),
                       self._get_timeout(read_timeout))
        else:
            timeout = self._get_timeout(timeout)
        return HTTPAdapter.send(self, request, stream=stream, timeout=timeout,
                                verify=verify, cert=cert, proxies=proxies)
