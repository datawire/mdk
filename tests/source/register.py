"""Register a service given on command-line args."""

import time
import sys

from mdk import init


def main():
    MDK = init()
    MDK.start()
    try:
        MDK.register(sys.argv[1], "1.0.0", sys.argv[2])
    finally:
        MDK.stop()
    time.sleep(30)

if __name__ == '__main__':
    main()
