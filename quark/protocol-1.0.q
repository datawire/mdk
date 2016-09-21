quark 1.0;

package datawire_mdk_protocol 2.0.14;

import quark.concurrent;
import quark.reflect;

include mdk_runtime.q;

import mdk_runtime;
import mdk_runtime.actors;

namespace mdk_protocol {

    class Discriminator {
        List<String> values;

        Discriminator(List<String> values) {
            self.values = values;
        }

        bool matches(String value) {
            int idx = 0;
            while (idx < values.size()) {
                if (value == values[idx]) {
                    return true;
                }
                idx = idx + 1;
            }
            return false;
        }
    }

    Discriminator anyof(List<String> values) {
        return new Discriminator(values);
    }

    class Serializable {
        @doc("""
        The given class must have a construct() static method that takes the JSON-encoded type,
        or a constructor that takes no arguments.
        """)
        static Serializable decodeClass(Class clazz, String encoded) {
            JSONObject json = encoded.parseJSON();
            String type = json["type"];
            Method meth = clazz.getMethod("construct");
            Serializable obj;
            if (meth != null) {
                obj = ?meth.invoke(null, [type]);
                if (obj == null) {
                    Logger logger = new Logger("protocol");
                    logger.warn(clazz.getName() + "." + meth.getName() + " could not understand this json: " + encoded);
                    return null;
                }
                clazz = obj.getClass();
            } else {
                obj = ?clazz.construct([]);
                if (obj == null) {
                    panic("could not construct " + clazz.getName() + " from this json: " + encoded);
                }
            }

            fromJSON(clazz, obj, json);

            return obj;
        }

        static Serializable decodeClassName(String name, String encoded) {
            return decodeClass(Class.get(name), encoded);
        }

        String encode() {
            Class clazz = self.getClass();
            JSONObject json = toJSON(self, clazz);
            Discriminator desc = ?self.getField("_discriminator");
            if (desc != null) {
                json["type"] = desc.values[0];
            }
            String encoded = json.toString();
            return encoded;
        }
    }

    @doc("""
        A Lamport Clock is a logical structure meant to allow partial causal ordering. Ours is a list of
        integers such that adding an integer implies adding a new level to the causality tree.

        Within a level, time is indicated by incrementing the clock, so

        [1,2,3] comes before [1,2,4] which comes before [1,2,5]

        Adding an element to the clock implies causality, so [1,2,4,1-N] is _by definition_ a sequence that was
        _caused by_ the sequence of [1,2,1-3].

        Note that LamportClock is lowish-level support. SharedContext puts some more structure around this, too.
    """)
    class LamportClock extends Serializable {
        // XXX Serialization breaks at the moment if this isn't a private element.
        Lock _mutex = new Lock();
        List<int> clocks = [];

        // XXX this could work a lot nicer with a parameterized method
        // in Serialize and a static class reference
        static LamportClock decode(String encoded) {
            return ?Serializable.decodeClassName("mdk_protocol.LamportClock", encoded);
        }

        @doc("""
            Return a neatly-formatted list of all of our clock elements (e.g. 1,2,4,1) for use as a name or
            a key.
        """)
        String key() {
            _mutex.acquire();

            List<String> tmp = [];

            int i = 0;

            while (i < self.clocks.size()) {
                tmp.add(self.clocks[i].toString());
                i = i + 1;
            }

            String str = ",".join(tmp);

            _mutex.release();

            return str;
        }

        // XXX Not automagically mapped to str() or the like, even though
        // something should be.
        String toString() {
            _mutex.acquire();

            String str = "<LamportClock " + self.key() + ">";

            _mutex.release();

            return str;
        }

        @doc("""
            Enter a new level of causality. Returns the value to pass to later pass to leave to get back to the
            current level of causality.
        """)
        int enter() {
            _mutex.acquire();

            int current = -1;

            self.clocks.add(0);
            current = self.clocks.size();

            _mutex.release();

            return current;
        }

        @doc("""
            Leave deeper levels of causality. popTo should be the value returned when you enter()d this level.
        """)
        int leave(int popTo) {
            _mutex.acquire();

            int current = -1;

            self.clocks = self.clocks.slice(0, popTo);
            current = self.clocks.size();

            _mutex.release();

            return current;
        }

        @doc("""
            Increment the clock for our current level of causality (which is always the last element in the list).
            If there are no elements in our clock, do nothing.
        """)
        void tick() {
            _mutex.acquire();

            int current = self.clocks.size();

            if (current > 0) {
                self.clocks[current - 1] = self.clocks[current - 1] + 1;
            }

            _mutex.release();
        }
    }

    class SharedContext extends Serializable {
        @doc("""
             Every SharedContext is given an ID at the moment of its
             creation; this is its traceId. Every operation started
             as a result of the thing that caused the SharedContext to
             be created must use the same SharedContext, and its
             traceId will _never_ _change_.
        """)
        String traceId = Context.runtime().uuid();

        @doc("""
            To track causality, we use a Lamport clock.
        """)
        LamportClock clock = new LamportClock();

        @doc("""
             We also provide a map of properties for later extension. Rememeber
             that these, too, will be shared across the whole system.
        """)
        Map<String, Object> properties = {};

        int _lastEntry = 0;

        SharedContext() {
            self._lastEntry = self.clock.enter();
        }

        @doc("""Set the traceId for this SharedContext.""")
        SharedContext withTraceId(String traceId) {
            self.traceId = traceId;
            return self;
        }

        // XXX this could work a lot nicer with a parameterized method
        // in Serialize and a static class reference
        static SharedContext decode(String encoded) {
            return ?Serializable.decodeClassName("mdk_protocol.SharedContext", encoded);
        }

        String clockStr(String pfx) {
            String cs = "";

            if (self.clock != null) {
                cs = pfx + self.clock.key();
            }

            return cs;
        }

        String key() {
            return self.traceId + self.clockStr(":");
        }

        // XXX Not automagically mapped to str() or the like, even though
        // something should be.
        String toString() {
            return "<SCTX t:" + self.traceId + self.clockStr(" c:") + ">";
        }

        @doc("""
            Tick the clock at our current causality level.
        """)
        void tick() {
            self.clock.tick();
        }

        @doc("""
            Return a SharedContext one level deeper in causality.

            NOTE WELL: THIS RETURNS A NEW SharedContext RATHER THAN MODIFYING THIS ONE. It is NOT SUPPORTED
            to modify the causality level of a SharedContext in place.
        """)
        SharedContext start_span() {
            // Tick first.
            self.tick();

            // Duplicate this object...
            SharedContext newContext = SharedContext.decode(self.encode());

            // ...open a new span...
            newContext._lastEntry = newContext.clock.enter();

            // ...and return the new context.
            return newContext;
        }

        @doc("""
            Return a SharedContext one level higher in causality. In practice, most callers should probably stop
            using this context, and the new one, after calling this method.

            NOTE WELL: THIS RETURNS A NEW SharedContext RATHER THAN MODIFYING THIS ONE. It is NOT SUPPORTED
            to modify the causality level of a SharedContext in place.
        """)
        SharedContext finish_span() {
            // Duplicate this object...
            SharedContext newContext = SharedContext.decode(self.encode());

            // ...leave...
            newContext._lastEntry = newContext.clock.leave(newContext._lastEntry);

            // ...and return the new context.
            return newContext;
        }

        @doc("Return a copy of a SharedContext.")
        SharedContext copy() {
            return SharedContext.decode(self.encode());
        }
    }

    interface ProtocolHandler {
        void onOpen(Open open);
        void onClose(Close close);
    }

    class ProtocolEvent extends Serializable {
        static ProtocolEvent construct(String type) {
            if (Open._discriminator.matches(type)) { return new Open(); }
            if (Close._discriminator.matches(type)) { return new Close(); }
            return null;
        }
        void dispatch(ProtocolHandler handler);
    }

    class Open extends ProtocolEvent {

        // Allow the old "mdk.protocol.Open" to work here.
        static Discriminator _discriminator = anyof(["open", "mdk.protocol.Open", "discovery.protocol.Open"]);

        String version = "2.0.0";
        Map<String,String> properties = {};

        void dispatch(ProtocolHandler handler) {
            handler.onOpen(self);
        }
    }

    // XXX: this should probably go somewhere in the library
    @doc("A value class for sending error informationto a remote peer.")
    class ProtocolError {
        @doc("Symbolic error code, alphanumerics and underscores only.")
        String code;

        @doc("Human readable short description.")
        String title;

        @doc("A detailed description.")
        String detail;

        @doc("A unique identifier for this particular occurrence of the problem.")
        String id;
    }

    @doc("Close the event stream.")
    class Close extends ProtocolEvent {

        // Allow the old "mdk.protocol.Close" to work here.
        static Discriminator _discriminator = anyof(["close", "mdk.protocol.Close", "discovery.protocol.Close"]);

        ProtocolError error;

        void dispatch(ProtocolHandler handler) {
            handler.onClose(self);
        }
    }

    @doc("Common protocol machinery for web socket based protocol clients.")
    class WSClient extends ProtocolHandler, Actor {

        /*

          # WSClient state machine

          ## External entity calls subclass.onStart()

          - subclass.onStart() or something else arranges for subclass.isStarted() to return true
          - WSClient.onStart() schedules .onExecute()
          - the Runtime delivers Hapenning message to .onMessage(), whihc calls .onScheduledEvent()
          - .onScheduledEvent() notices not .isConnected() and subclass.isStarted() so eventually calls .doOpen(),
            then schedules itself for execution again
          - .doOpen() calls .open() using subclass.url() and manages retries/backoff
          - .open() calls subclass.token() and constructs a real URL, then calls WebSockets.connect()
          - the resulting promise calls .onWSConnected()
          - .onWSConnected() saves the socket for .isConnected() to check,
            then sends an Open protocol oevent, calls subclass.startup(), calls subclass.pump()
          - the ScheduleActor send a Happening message to .onMessage(), which calls onScheduledEvent
          - .onScheduledEvent() notices .isConnected() and subclass.isStarted() so
            calls subclass.pump() and maybe .doHeartbeat()
            then schedules itself for execution again
          - .doHeartbeat() calls subclass.heartbeat() and tracks heartbeat timing

          ## ELB or something kills the connection randomly

          - the Runtime maybe calls .onWSError()
          - .onWSError() logs and calls .doBackoff()
          - .doBackoff() computes backoff timing stuff
          - the Runtime maybe calls .onWSClosed(), which does nothing
          - the Runtime calls .onWSFinal()
          - .onWSFinal() nulls out the saved socket so .isConnected() will return false
          - the ScheduleActor sends message to .onMessage(), which calls .onScheduledEvent()
          - .onScheduledEvent() notices not .isConnected() and subclass.isStarted() so eventually calls .doOpen(),
            then schedules itself for execution again -- see above

          Note that subclass.shutdown() is not called in this case, but subclass.startup() is called.

          ## Something arranges for subclass.isStarted() to return false

          - the ScheduleActor sends message to .onMessage(), which calls onScheduledEvent()
          - onScheduledEvent() notices .isConnected() and not .isStarted() so
            it calls subclass.shutdown(), closes the socket, and
            nulls out the saved socket so .isConnected() will return false
            then does not schedule itself for execution again

          Must override: .isStarted(), .url(), .token()
          May Override: .startup(), .pump(), .heartbeat(), .onWSMessage()

        */

        Logger logger = new Logger("protocol");

        float firstDelay = 1.0;
        float maxDelay = 16.0;
        float reconnectDelay = firstDelay;
        float ttl = 30.0;
        float tick = 1.0;

        WSActor sock = null;
        String sockUrl = null;

        long lastConnectAttempt = 0L;
        long lastHeartbeat = 0L;

        Time timeService;
        Actor schedulingActor;
        WebSockets websockets;
        MessageDispatcher dispatcher;

        WSClient(MDKRuntime runtime) {
            self.dispatcher = runtime.dispatcher;
            self.timeService = runtime.getTimeService();
            self.schedulingActor = runtime.getScheduleService();
            self.websockets = runtime.getWebSocketsService();
        }

        String url();
        String token();
        bool isStarted();

        bool isConnected() {
            return sock != null;
        }

        void schedule(float time) {
            self.dispatcher.tell(self, new Schedule("wakeup", time), self.schedulingActor);
        }

        void scheduleReconnect() {
            schedule(reconnectDelay);
        }

        void onOpen(Open open) {
            // Should assert version here ...
        }

        void doBackoff() {
            reconnectDelay = 2.0*reconnectDelay;

            if (reconnectDelay > maxDelay) {
                reconnectDelay = maxDelay;
            }
            logger.info("backing off, reconnecting in " + reconnectDelay.toString() + " seconds");
        }

        void onClose(Close close) {
            logger.info("close: " + close.toString());
            if (close.error == null) {
                reconnectDelay = firstDelay;
            } else {
                doBackoff();
            }
        }

        // Actor interface:
        void onStart(MessageDispatcher dispatcher) {
            schedule(0.0);
        }

        void onStop() {
            if (isConnected()) {
                shutdown();
                self.dispatcher.tell(self, new WSClose(), sock);
                sock = null;
            }
        }

        void onMessage(Actor origin, Object message) {
            String typeId = message.getClass().id;
            if (typeId == "mdk_runtime.Happening") {
                self.onScheduledEvent();
                return;
            }
            if (typeId == "mdk_runtime.WSClosed") {
                self.onWSClosed();
                return;
            }
            if (typeId == "mdk_runtime.WSMessage") {
                WSMessage wsmessage = ?message;
                self.onWSMessage(wsmessage.body);
                return;
            }
        }

        void onScheduledEvent() {
            /*
              Do our periodic chores here, this will involve checking
              the desired state held by disco against our actual
              state and taking any measures necessary to address the
              difference:


              - isStarted() holds the desired connectedness
              state. The isConnected() accessor holds the actual
              connectedness state. If these differ then do what is
              necessry to make the desired state actual.

              - If we haven't sent a heartbeat recently enough, then
              do that.
            */

            long rightNow = (self.timeService.time()*1000.0).round();
            long heartbeatInterval = ((ttl/2.0)*1000.0).round();
            long reconnectInterval = (reconnectDelay*1000.0).round();

            if (isConnected()) {
                if (isStarted()) {
                    pump();
                    if (rightNow - lastHeartbeat >= heartbeatInterval) {
                        doHeartbeat();
                    }
                }
            } else {
                if (isStarted() && (rightNow - lastConnectAttempt) >= reconnectInterval) {
                    doOpen();
                }
            }

            if (isStarted()) {
                schedule(tick);
            }
        }

        void doOpen() {
            open(url());
            lastConnectAttempt = (self.timeService.time()*1000.0).round();
        }

        void doHeartbeat() {
            heartbeat();
            lastHeartbeat = (self.timeService.time()*1000.0).round();
        }

        void open(String url) {
            sockUrl = url;
            String tok = token();
            if (tok != null) {
                url = url + "?token=" + tok;
            }

            logger.info("opening " + sockUrl);

            self.websockets.connect(url, self)
                .andEither(bind(self, "onWSConnected", []),
                           bind(self, "onWSError", []));
        }

        void startup() {}

        void pump() {}

        void heartbeat() {}

        void shutdown() {}

        void onWSMessage(String message) {
            // Override in subclasses
        }

        void onWSConnected(WSActor socket) {
            // Whenever we (re)connect, notify the server of any
            // nodes we have registered.
            logger.info("connected to " + sockUrl + " via " + socket.toString());

            reconnectDelay = firstDelay;
            sock = socket;

            self.dispatcher.tell(self, new Open().encode(), sock);

            startup();
            pump();
        }

        void onWSError(Error error) {
            logger.error("onWSError in protocol! " + error.toString());
            // Any non-transient errors should be reported back to the
            // user via any Nodes they have requested.
            doBackoff();
        }

        void onWSClosed() {
            logger.info("closed " + sockUrl);
            sock = null;
        }
    }

}
