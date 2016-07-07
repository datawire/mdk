import logging
logging.basicConfig(level=logging.INFO)

import tracing

tracer = tracing.Tracer.withURLsAndToken("wss://tracing-develop.datawire.io/ws", None, None)

tracer.startRequest("http://req1")
tracer.log("INFO", "flynntest", "testing from Flynn...")
tracer.endRequest();

