"""Resolve a service given on command-line.

First argument: service to resolve.
Second argument, optional: encoded session.
"""

import sys, traceback
import logging
logging.basicConfig(level=logging.INFO)

from mdk import init


def main():
    MDK = init()
    MDK.start()
    encoded_session = None
    if len(sys.argv) > 2:
        encoded_session = sys.argv[2]
    ssn = MDK.join(encoded_session)
    try:
        address = ssn.resolve_until(sys.argv[1], "1.0.0", 10.0).address
    except:
        exc = traceback.format_exc()
        if "Timeout" not in exc:
            sys.stderr.write(exc)
            sys.stderr.flush()
        address = "not found"
    sys.stdout.write(address)
    sys.stdout.flush()
    MDK.stop()


if __name__ == '__main__':
    main()
