"""
Python standard library ``logging`` support for MDK.
"""

from __future__ import absolute_import

from logging import StreamHandler


class MDKHandler(StreamHandler):
    """Hand log messages to an MDK Session."""

    def __init__(self, mdk, get_session):
        """
        :param mdk: A ``mdk.MDK`` instance.
        :param get_session: Unary callable that returns the current MDK Session, or
            ``None``, in which case a default Session will be used.
        """
        StreamHandler.__init__(self)
        self._default_session = mdk.session()
        self._get_session = get_session

    def emit(self, record):
        level = record.levelname
        if level == "WARNING":
            level = "WARN"
        session = self._get_session()
        if session is None:
            session = self._default_session
        getattr(session, level.lower())(record.name, self.format(record))
