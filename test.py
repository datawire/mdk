import logging
logging.basicConfig(level=logging.INFO)

import tracing

tracer = tracing.Tracer()
tracer.log("DEBUG", "test", "testing...")
