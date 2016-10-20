"""
Create an encoded MDK context and write it to standard out.
"""

import sys

from mdk import start


if __name__ == '__main__':
    mdk = start()
    session = mdk.session()
    session.setDeadline(5.0)
    sys.stdout.write(session.externalize())
    sys.stdout.flush()
    mdk.stop()
