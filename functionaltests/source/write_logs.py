"""Write some logs."""
from __future__ import print_function

import sys
import time
import os
import logging
logging.basicConfig(stream=sys.stderr, level=logging.DEBUG)

from mdk import start
mdk = start()

start = time.time()

def main():
    session = mdk.session()
    session.trace("DEBUG")
    category = sys.argv[1]
    results = set()
    expected = set(("hello {} {}".format(category, level), level.upper())
                   for level in ["critical", "error", "warn", "info", "debug"])

    def got_message(event):
        if time.time() - start > 60:
            print("Took more than 60 seconds, giving up.")
            os._exit(1)

        print((event.category, event.text))
        if event.category == category:
            results.add((event.text, event.level))
        if expected == results:
            print("Got expected messages!")
            mdk.stop()
            # XXX working around Quark/MDK issue where Python runtime isn't exiting:
            os._exit(0)
        else:
            print("No full results yet. Specifically got: " + repr(event))

    mdk._tracer.subscribe(got_message)
    time.sleep(1)
    for level in ["critical", "error", "warn", "info", "debug"]:
        f = getattr(session, level)
        f(category, "hello {} {}".format(category, level))


if __name__ == '__main__':
    main()
