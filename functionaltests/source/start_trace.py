"""Write some logs to the given tracing session."""

import sys
import time

from mdk import start
mdk = start()


def main():
    context = sys.argv[1]
    session = mdk.join(context)
    session.info("process1", "hello")
    time.sleep(5)  # make sure it's written
    sys.stdout.write(session.inject())
    sys.stdout.flush()
    mdk.stop()


if __name__ == '__main__':
    main()
