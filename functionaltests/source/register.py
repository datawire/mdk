"""Register a service given on command-line args."""
from __future__ import print_function

import time
import sys
import logging
import signal

logging.basicConfig(level=logging.INFO)

from mdk import init


def exit(*args):
    raise SystemExit
signal.signal(signal.SIGTERM, exit)

def main():
    MDK = init()
    MDK.start()
    try:
        MDK.register(sys.argv[1], "1.0.0", sys.argv[2])
        time.sleep(30)
    finally:
        print("Shutting down...")
        MDK.stop()


if __name__ == '__main__':
    main()
