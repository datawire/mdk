"""Write some logs."""
from __future__ import print_function

import sys

from mdk import start
mdk = start()

import read_logs

def main():
    context = sys.argv[1]
    expected = set([("process1", "hello"), ("process2", "world")])
    session = mdk.join(context)
    session.info("process2", "world")
    read_logs.Retriever(context, expected, mdk).read_logs()

if __name__ == '__main__':
    main()
