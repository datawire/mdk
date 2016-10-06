"""Write some logs."""
from __future__ import print_function

import sys
import time

from mdk import start
mdk = start()


def main():
    context = sys.argv[1]
    session = mdk.join(context)
    session.info("process2", "world")
    time.sleep(3)  # make sure it's written
    mdk.stop()

if __name__ == '__main__':
    main()
