"""Create a new session for the trace."""

import sys

from mdk import start
mdk = start()


def main():
    session = mdk.session()
    sys.stdout.write(session.inject())
    sys.stdout.flush()
    mdk.stop()


if __name__ == '__main__':
    main()
