"""Write some logs."""

import sys

from mdk import init


def main():
    MDK = init()
    MDK.start()
    session = MDK.session()
    category = sys.argv[1]

    for level in ["critical", "error", "warn", "info", "debug"]:
        f = getattr(session, level)
        f(category, "hello {} {}".format(category, level))
    MDK.stop()

if __name__ == '__main__':
    main()
