import logging
logging.basicConfig(level=logging.INFO)

import msdk, requests, traceback

def bizlogic(m):
    n = m.resolve_until("asdf", "1.0", 10.0)
    m.info("bizlogic", "Querying... %s" % n.address)
    requests.get(n.address)

m = msdk.init()

m.start()
try:
    m.register("asdf", "1.0", "http://localhost")
    try:
        m.protect(bizlogic)
    except:
        m.fail(traceback.format_exc())
finally:
    m.stop()
