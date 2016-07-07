import logging, traceback, threading, atexit
#logging.basicConfig(level=logging.INFO)

from flask import Flask
app = Flask(__name__)

import msdk
m = msdk.init()

def protect(fun):
    def doit():
        try:
            m.begin()
            return fun(m)
        except:
            m.fail(traceback.format_exc())
            raise
        else:
            m.end()
    return doit

lock = threading.Lock()

events = []

def addEvents(e):
    global events
    with lock:
        events.extend(e)
        events = events[-10:]
def poll():
    m._tracer.poll().andThen(addEvents)
    global thread
    thread = threading.Timer(1, poll, ())
    thread.start()

thread = threading.Timer(1, poll, ())


@app.route("/")
@protect
def hello(m):
    with lock:
        return "<html><head><meta http-equiv=\"refresh\" content=1><body><ul>" + \
            "\n".join(["<li>%s</li>" % e.toString().replace("<", "&lt;").replace(">", "&gt;")
                       for e in events]) + \
            "</body></html>"

m.start()
atexit.register(m.stop)

host = "localhost"
port = 5000
m.register("console", "1.0", "http://%s:%s" % (host, port))

thread.start()
app.run(host=host, port=port)
