import logging
logging.basicConfig(level=logging.DEBUG)

import tracing

tracer = tracing.Tracer()
result = None

def goodHandler(res):
	global result
	print("Good!")

	for record in res.result:
		print(formatLogRecord(record))
		
def badHandler(result):
	print("Failure: %s" % result.toString())

def formatLogRecord(record):
	return("%.3f %s %s" % (record.timestamp, record.record.level, record.record.text))

tracer.query(1467045724000, 1467045780000).andEither(goodHandler, badHandler)
