"""Resolve a service given on command-line."""

import sys

from mdk import init


def main():
    MDK = init()
    MDK.start()
    sys.stdout.write(MDK.resolve(sys.argv[1], "1.0.0").address)
    sys.stdout.flush()

if __name__ == '__main__':
    main()
