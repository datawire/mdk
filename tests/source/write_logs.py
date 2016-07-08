"""Write some logs."""

import sys
import time
import os

from mdk import start
mdk = start()

start = time.time()

def got_logs(log_events):
    category = sys.argv[1]
    results = set()
    for event in log_events.result:
        print(event.category, event.text)
        if event.category == category:
            results.add((event.text, event.level))
    expected = set(("hello {} {}".format(category, level), level.upper())
                   for level in ["critical", "error", "warn", "info", "debug"])
    if expected == results:
        print("Got expected messages!")
        mdk.stop()
        # XXX working around Quark/MDK issue where Python runtime isn't exiting:
        os._exit(0)
    else:
        print("No full results yet, will try again. Specifically got: " + repr(results))
        read_logs()

def got_error(error):
    print("ERROR: " + error.toString())
    mdk.stop()
    os._exit(1)

def read_logs():
    if time.time() - start > 60:
        print("Took more than 60 seconds, giving up.")
        os._exit(1)
    tracer = mdk._tracer
    print(tracer.url)
    print(tracer.queryURL)
    now = int(start * 1000)
    tracer.query(now - 60000, now + 120000).andEither(got_logs, got_error)

def main():
    session = mdk.session()
    category = sys.argv[1]

    for level in ["critical", "error", "warn", "info", "debug"]:
        f = getattr(session, level)
        f(category, "hello {} {}".format(category, level))
    read_logs()

if __name__ == '__main__':
    main()
