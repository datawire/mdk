"""Write some logs."""

import sys
import time

from mdk import start
mdk = start()


def main():
    session = mdk.session()
    session.info("process1", "hello")
    time.sleep(5)
    sys.stdout.write(session.inject())
    sys.stdout.flush()
    mdk.stop()


if __name__ == '__main__':
    main()
