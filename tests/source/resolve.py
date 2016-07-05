"""Resolve a service given on command-line."""

import sys
import logging
logging.basicConfig(level=logging.INFO)

from mdk import init


def main():
    MDK = init()
    MDK.start()
    try:
        sys.stdout.write(MDK.resolve_until(sys.argv[1], "1.0.0", 10.0).address)
        sys.stdout.flush()
    finally:
        MDK.stop()


if __name__ == '__main__':
    main()
