import logging
#logging.basicConfig(level=logging.INFO)

import msdk

def bizlogic(m):
    n = m.resolve("asdf", "1.0")
    n.await(10.0)
    try:
        print n.address
    except Exception, e:
        m.fail(e.getMessage())

m = msdk.init()

m.start()
try:
    m.register("asdf", "1.0", "http://localhost")
    m.protect(bizlogic)
finally:
    m.stop()
