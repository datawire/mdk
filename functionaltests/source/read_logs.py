"""
Read logs, ensure they contain expected results.

Usage: read_logs.py <context_id> <expected-messages>

The expected messages are passed as JSON-encoded parameter, a list of
[<category>, <text>] lists.
"""
from __future__ import print_function

import os
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
        self.results = set()

    def _got_log(self, event):
        print(event.context, event.category, event.text)
        if event.context.traceId in self.context:
            self.results.add((event.category, event.text))

        if self.expected == self.results:
            print("Got expected messages!")
            self.mdk.stop()
            os._exit(0)  # Some MDK bug or something
        else:
            print("No full results yet, will keep trying: {} != {}".format(
                self.expected, self.results))
            if time.time() - self.start > 60:
                print("Took more than 60 seconds, giving up.")
                self.mdk.stop()
                sys.exit(1)

    def _got_error(self, error):
        print("ERROR: " + error.toString())
        self.mdk.stop()
        sys.exit(1)

    def read_logs(self):
        self.mdk._tracer.subscribe(self._got_log)


def main():
    mdk = start()
    context = sys.argv[1]
    expected = set([tuple(l) for l in loads(sys.argv[2])])
    Retriever(context, expected, mdk).read_logs()


if __name__ == '__main__':
    main()
