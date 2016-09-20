"""
Create an encoded MDK context and write it to standard out.
"""

import sys

from mdk import start


if __name__ == '__main__':
    mdk = start()
    sys.stdout.write(mdk.session().externalize())
    sys.stdout.flush()
    mdk.stop()
