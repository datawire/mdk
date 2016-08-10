"""discowatch.py

Watch the disco's traces.

Usage: 
    discowatch.py [options]

Options:
    -l <minlevel>        set the minimum log level to output
    -c <category>        output only logs with this category
    -s <service>         output only logs from this service
    -t <traceId>         output only logs for this traceId
    --node-id <nodeId>   output only logs involving this nodeId
    --depth <depth>      output only the top <depth> levels of the causality tree
    -f                   stay connected and continue watching
    -n <count>           output only <count> log messages
"""

from docopt import docopt
import mdk
import threading
import datetime


# setInterval function
def set_interval(func, sec):
    def func_wrapper():
        set_interval(func, sec)
        func()
    t = threading.Timer(sec, func_wrapper)
    t.start()
    return t


# sends a message that will be ignored but will keep the socket open / avoid timeout
def heartbeat():
    ack = mdk.mdk_tracing.protocol.LogAck

# function that will run heartbeat every N seconds
def heartbeater():
    set_interval(heartbeat, 15000)
    
class TraceEventHandler (object):
    def __init__(self, args):
        """ Initialize a TraceEventHandler with a set of args from docopt. """
        self.args = args

    def traceEvent(self, event):
        # how do i get the correct timeSinceStart? need the actual startTime to get timeSinceStart
        timestamp = event.timestamp/1000.0
        date = datetime.datetime.fromtimestamp(timestamp).isoformat()
        date = date[:-3]
        clock = ""
        category = event.category
        level = event.level
        text = event.text
        traceId = event.context.traceId

        if event.context:
            lclock = event.context.clock

            if lclock:
                clock = lclock.key()

        eventStr = date+ " " + traceId + " " + clock + " " + category + " " + level + " " + text

        print(eventStr)

# Program we are running
def main(docopt_args):
    # Create a new Tracer
    tracer = mdk.mdk_tracing.Tracer(mdk.mdk_runtime.defaultRuntime())

    # Create a new TraceEventHandler
    traceEventHandler = TraceEventHandler(docopt_args)

    if docopt_args["-f"]:
        # ...and subscribe to receive log events as they come in over the wire.
            # takes only 1 parameter 
            # opens a connection if needed (_openIfNeeded())
            # runs _client.subscribe with a parameter
                # locks in something, handler = patameter, start if needed, then release
                # subscribe takes a function, which takes an event, which a log event
        tracer.subscribe(traceEventHandler.traceEvent)
  
# START OF SCRIPT
if __name__ == "__main__":
    # Docopt will check all arguments, and exit with the Usage string if they don't pass.
    args = docopt(__doc__)

    # We have valid args, so run the program.
    main(args)