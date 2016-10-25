"""
Python standard library ``logging`` support for MDK.
"""

from __future__ import absolute_import

from logging import StreamHandler


class MDKHandler(StreamHandler):
    """Hand log messages to an MDK Session."""

    def __init__(self, get_session):
        """
        :param get_session: Unary callable that returns the current MDK Session.
        """
        StreamHandler.__init__(self)
        self._get_session = get_session

    def emit(self, record):
        level = record.levelname
        if level == "WARNING":
            level = "WARN"
        session = self._get_session()
        getattr(session, level.lower())(record.name, self.format(record))
