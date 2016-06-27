import logging
logging.basicConfig(level=logging.INFO)

import tracing

logger = tracing.Logger()
logger.log(logging.DEBUG, "test", "testing...")
