"""Read some logs."""

from __future__ import print_function

import sys
import time

from mdk import init
mdk = init()
mdk.start()

def got_logs(log_events):
    mdk.stop()
    category = sys.argv[1]
    results = set()
    for event in log_events.result:
        if event.category == category:
            results.add((event.text, event.level))
    expected = set(("hello {} {}".format(category, level), level.upper())
                   for level in ["critical", "error", "warn", "info", "debug"])
    if expected == results:
        print("Got expected messages!")
        sys.exit(0)
    else:
        print("Got unexpected result: " + repr(results))
        sys.exit(1)

def main():
    tracer = mdk._tracer
    now = int(time.time() * 1000)
    tracer.query(now - 10000, now + 10000).andFinally(got_logs)


if __name__ == '__main__':
    main()
