import logging
logging.basicConfig(level=logging.DEBUG)

import tracing
import time

# tracer = tracing.Tracer.withURLsAndToken("ws://localhost:52690/ws", None, "fakeToken")
tracer = tracing.Tracer.withURLsAndToken("wss://tracing-develop.datawire.io/ws", None, None)

def goodHandler(result):
	print("Good!")

	for record in result:
		print(record.toString())
		
def badHandler(result):
	print("Failure: %s" % result.toString())

def formatLogRecord(record):
	return("%.3f %s %s" % (record.timestamp, record.record.level, record.record.text))

tracer.poll().andEither(goodHandler, badHandler)
