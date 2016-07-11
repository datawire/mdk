"""Write some logs."""

import sys
import time
import os

from mdk import start
mdk = start()

start = time.time()

def got_logs(log_events, context):
    results = set()
    for event in log_events.result:
        print event.context, event.category, event.text
        if event.context.traceId in context:
            results.add((event.category, event.text))
    expected = set([("process1", "hello"), ("process2", "world")])

    if expected == results:
        print("Got expected messages!")
        mdk.stop()
        # XXX working around Quark/MDK issue where Python runtime isn't exiting:
        os._exit(0)
    else:
        print("No full results yet, will try again. Specifically got: " + repr(results))
        read_logs(context)

def got_error(error):
    print("ERROR: " + error.toString())
    mdk.stop()
    os._exit(1)

def read_logs(context):
    if time.time() - start > 60:
        print("Took more than 60 seconds, giving up.")
        os._exit(1)
    tracer = mdk._tracer
    now = int(start * 1000)
    tracer.query(now - 60000, now + 120000).andEither(
        lambda events: got_logs(events, context), got_error)

def main():
    context = sys.argv[1]
    session = mdk.join(context)
    session.info("process2", "world")

    read_logs(context)

if __name__ == '__main__':
    main()
