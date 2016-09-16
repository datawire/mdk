"""
Read logs, ensure they contain expected results.

Usage: read_logs.py <context_id> <expected-messages>

The expected messages are passed as JSON-encoded parameter, a list of
[<category>, <text>] lists.
"""
from __future__ import print_function

import sys
import time
from json import loads

from mdk import start


class Retriever(object):
    """Retrieve logs, make sure they include expected messages."""

    def __init__(self, context, expected, mdk):
        self.context = context
        self.expected = expected
        self.mdk = mdk
        self.start = time.time()

    def _got_logs(self, log_events):
        results = set()
        for event in log_events.result:
            print(event.context, event.category, event.text)
            if event.context.traceId in self.context:
                results.add((event.category, event.text))

        if self.expected == results:
            print("Got expected messages!")
            self.mdk.stop()
        else:
            print("No full results yet, will try again. Specifically got: " + repr(results))
            self.read_logs()

    def _got_error(self, error):
        print("ERROR: " + error.toString())
        self.mdk.stop()
        sys.exit(1)

    def read_logs(self):
        if time.time() - self.start > 60:
            print("Took more than 60 seconds, giving up.")
            sys.exit(1)
        tracer = self.mdk._tracer
        now = int(self.start * 1000)
        tracer.query(now - 60000, now + 120000).andEither(self._got_logs,
                                                          self._got_error)


def main():
    mdk = start()
    context = sys.argv[1]
    expected = set(loads(sys.argv[1]))
    Retriever(context, expected, mdk).read_logs()


if __name__ == '__main__':
    main()
