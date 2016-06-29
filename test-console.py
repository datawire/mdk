import logging
logging.basicConfig(level=logging.DEBUG)

import tracing
import time

import quark

# tracer = tracing.Tracer.withURLsAndToken("ws://localhost:52690/ws", None, "fakeToken")
tracer = tracing.Tracer.withURLsAndToken("wss://tracing-develop.datawire.io/ws", None, None)

def goodHandler(result):
	# logging.info("Good!")

	for record in result:
		logging.info(record.toString())
		
def badHandler(result):
	logging.info("Failure: %s" % result.toString())

def formatLogRecord(record):
	return("%.3f %s %s" % (record.timestamp, record.record.level, record.record.text))

def poller(hrm=None):
	# logging.info("POLLING")

	tracer.poll() \
	      .andEither(goodHandler, badHandler) \
	      .andFinally(lambda x: quark.IO.schedule(1)) \
	      .andFinally(poller)

poller()
