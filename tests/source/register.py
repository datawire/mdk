"""Register a service given on command-line args."""

import time
import sys
import logging
logging.basicConfig(level=logging.INFO)

from mdk import init


def main():
    MDK = init()
    MDK.start()
    try:
        MDK.register(sys.argv[1], "1.0.0", sys.argv[2])
        time.sleep(30)
    finally:
        MDK.stop()


if __name__ == '__main__':
    main()
