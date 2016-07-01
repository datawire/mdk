import logging
logging.basicConfig(level=logging.DEBUG)

import functools
import mdk
import uuid
import time

EVENT_TIMES = {
    'RELEASE': 1468414800,      # 20160713T090000-0400
    'CHRISTMAS': 1482642000,    # 20161225T000000-0400
    'OLYMPICS': 1489464000      # 20170314T000000-0500
}

def logAndSleep(m, cat, msg):
    m.info(cat, msg)
    time.sleep(1)

# Decorator to turn a function into a "service"
def service(callable):
    svcProcUUID = str(uuid.uuid4()).upper()

    @functools.wraps(callable)
    def callable_as_service(*args, **kwargs):
        print("calling as service (%s)" % svcProcUUID)

        # hackery here
        encodedContext = m.context().encode()

        m.start_interaction()
        time.sleep(1)
        m.context().withProcUUID(svcProcUUID)
        result = callable(*args, **kwargs)
        m.finish_interaction()
        time.sleep(1)

        # hackery here
        m.join_encoded_context(encodedContext)
        m.context().tick()
        
        return result

    return callable_as_service

@service
def foundation_release(now):
    delta = EVENT_TIMES['RELEASE'] - now
    logAndSleep(m, "foundation_release", "%d - %d == %d" % (now, EVENT_TIMES['RELEASE'], delta))
    return delta

@service
def foundation_christmas(now):
    delta = EVENT_TIMES['CHRISTMAS'] - now
    logAndSleep(m, "foundation_christmas", "%d - %d == %d" % (now, EVENT_TIMES['CHRISTMAS'], delta))
    return delta

@service
def foundation_olympics(now):
    delta = EVENT_TIMES['OLYMPICS'] - now
    logAndSleep(m, "foundation_olympics", "%d - %d == %d" % (now, EVENT_TIMES['OLYMPICS'], delta))
    return delta


EVENT_HANDLERS = {
    'RELEASE': foundation_release,
    'CHRISTMAS': foundation_christmas,
    'OLYMPICS': foundation_olympics,
}

@service
def current_time():
    result = int(time.time())

    logAndSleep(m, "current_time", "now is %d" % result)

    return result

@service
def delta_time(now, event):
    logAndSleep(m, "delta_time", "%d, looking for %s" % (now, event))

    svcFunc = EVENT_HANDLERS[event]

    if svcFunc:
        result = svcFunc(now)
        logAndSleep(m, "delta_time", "%d, %s @ delta %d" % (now, event, result))

        return result
    else:
        m.error("delta_time", "%d, %s is not found" % (now, event))

        return None

import mdk
m = mdk.init()
m.start()

logAndSleep(m, "mainline", "get-times starting")

m._tracer.startRequest("get-times")
time.sleep(1)

logAndSleep(m, "mainline", "getting current time")

now = current_time()

logAndSleep(m, "mainline", "current time %d" % now)

delta = delta_time(now, 'RELEASE')

logAndSleep(m, "mainline", "time till release: %ds" % delta)

delta = delta_time(now, 'CHRISTMAS')

logAndSleep(m, "mainline", "time till Christmas: %ds" % delta)

delta = delta_time(now, 'OLYMPICS')

logAndSleep(m, "mainline", "time till Olympics: %ds" % delta)

m._tracer.endRequest()
