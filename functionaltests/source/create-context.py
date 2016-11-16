"""
Create an encoded MDK context and write it to standard out.
"""

import sys
import os

from mdk import start


if __name__ == '__main__':
    mdk = start()
    session = mdk.session()
    session.setDeadline(5.0)
    sys.stdout.write(session.externalize())
    sys.stdout.flush()
    # mdk.stop() takes as much as 2 seconds, which messes up the timestamp on
    # the 5 second delay by using up a chunk of those 5 seconds. So just exit
    # without cleanup:
    os._exit(0)
