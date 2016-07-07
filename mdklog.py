#!python

"""mdklog.py

Send a log message to the MDK Tracing service

Usage: 
    mdklog.py [options] <text>...

Options:
	-c <category>, --category <category> Set log category [default: None]
	-l <level>, --level <level>          Set log level [default: INFO]
	--traceid=<traceID>                  Set trace ID
	--start=<url>                        Send startRequest
	--stop                               Send stopRequest
"""

from docopt import docopt

import logging
logging.basicConfig(level=logging.DEBUG)

import mdk_tracing

args = docopt(__doc__, version="mdklog {0}".format("0.1.0"))

# tracer = mdk_tracing.Tracer.withURLsAndToken("wss://tracing-develop.datawire.io/ws", None, None)
tracer = mdk_tracing.Tracer.withURLsAndToken("ws://localhost:52690/ws", None, None)

print(tracer.getContext().toString())

level = args.get("<level>", "INFO")
category = args.get("<category>", "None")

tracer.log(level, category, " ".join(args["<text>"]))
