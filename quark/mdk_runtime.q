quark 1.0;

package datawire_mdk_runtime 2.0.14;

include actors_core.q;
include actors_promise.q;
include mdk_runtime_files.q;

import quark.os;
import mdk_runtime.actors;
import mdk_runtime.promise;


namespace mdk_runtime {
    @doc("Trivial dependency injection setup.")
    class Dependencies {
        Map<String,Object> _services = {};

        @doc("Register a service object.")
        void registerService(String name, Object service) {
            if (self._services.contains(name)) {
                panic("Can't register service '" + name + "' twice.");
            }
            self._services[name] = service;
        }

        @doc("Look up a service by name.")
        Object getService(String name) {
            if (!self._services.contains(name)) {
                panic("Service '" + name + "' not found!");
            }
            return self._services[name];
        }

        @doc("Return whether the service exists.")
        bool hasService(String name) {
            return self._services.contains(name);
        }

    }

    @doc("""
    Runtime environment for a particular MDK instance.

    Required registered services:
    - 'time': A provider of mdk_runtime.Time;
    - 'schedule': Implements the mdk_runtime.ScheduleActor actor protocol.
    - 'websockets': A provider of mdk_runtime.WebSockets.
    """)
    class MDKRuntime {
        Dependencies dependencies = new Dependencies();
        MessageDispatcher dispatcher = new MessageDispatcher();

        @doc("Return Time service.")
        Time getTimeService() {
            return ?self.dependencies.getService("time");
        }

        @doc("Return Schedule service.")
        Actor getScheduleService() {
            return ?self.dependencies.getService("schedule");
        }

        @doc("Return WebSockets service.")
        WebSockets getWebSocketsService() {
            return ?self.dependencies.getService("websockets");
        }

        @doc("Return File service.")
        mdk_runtime.files.FileActor getFileService() {
            return ?self.dependencies.getService("files");
        }

        @doc("Return EnvironmentVariables service.")
        EnvironmentVariables getEnvVarsService() {
            return ?self.dependencies.getService("envvar");
        }

        @doc("Stop all Actors that are started by default (i.e. files, schedule).")
        void stop() {
            self.dispatcher.stopActor(getFileService());
            self.dispatcher.stopActor(self.getScheduleService());
            self.dispatcher.stopActor(self.getWebSocketsService());
        }
    }

    @doc("""
    Return current time.
    """)
    interface Time {
        @doc("""
        Return the current time in seconds since the Unix epoch.
        """)
        float time();
    }

    @doc("""
    An actor that can schedule events.

    Accepts Schedule messages and send Happening events to originator at the
    appropriate time.
    """)
    interface SchedulingActor extends Actor {}

    @doc("""
    Service that can open new WebSocket connections.

    When stopped it should close all connections.
    """)
    interface WebSockets extends Actor {
        @doc("""
        The Promise resolves to a WSActor or WSConnectError. The originator will
        receive messages.
        """)
        mdk_runtime.promise.Promise connect(String url, Actor originator);
    }

    @doc("Connection failed.")
    class WSConnectError extends Error {
        String toString() {
            return "<WSConnectionError: " + super.toString() + ">";
        }
    }

    @doc("""
    Actor representing a specific WebSocket connection.

    Accepts String and WSClose messages, sends WSMessage and WSClosed
    messages to the originator of the connection (Actor passed to
    WebSockets.connect()).
    """)
    interface WSActor extends Actor {}

    @doc("A message was received from the server.")
    class WSMessage {
        String body;

        WSMessage(String body) {
            self.body = body;
        }
    }

    @doc("Tell WSActor to close the connection.")
    class WSClose {}

    @doc("Notify of WebSocket connection having closed.")
    class WSClosed {}

    @doc("""
    WSActor that uses current Quark runtime as temporary expedient.

    State can be 'ERROR', 'CONNECTING', 'CONNECTED', 'DISCONNECTING',
    'DISCONNECTED'.
    """)
    class QuarkRuntimeWSActor extends WSActor, WSHandler {
        // XXX need better story for logging; perhaps integrate MDK Session with
        // the MessageDispatcher?
        Logger logger = new Logger("protocol");
        WebSocket socket;
        PromiseResolver factory;
        Actor originator;
        MessageDispatcher dispatcher;
        String state = "CONNECTING";
        List<Object> incoming = [];  // FIXME: WS Messages received before actor has started

        QuarkRuntimeWSActor(Actor originator, PromiseResolver factory) {
            self.originator = originator;
            self.factory = factory;
        }

        // Debugging
        void logTS(String message) {
            long now = Context.runtime().now();
            int tenths = (now.truncateToInt() / 100) % 100000;  // in tenths of seconds
            float seconds = tenths.toFloat() / 10.0;
            logger.debug(seconds.toString() + " " + message);
        }

        void logPrologue(String what) {
            String disMessage = "";
            if (self.dispatcher == null) {
                disMessage = ", no dispatcher";
            }
            logTS(what +
                  ", current state " + self.state +
                  ", originator " + self.originator.toString() +
                  ", I am " + self.toString() +
                  disMessage);
        }

        // Actor
        void onStart(MessageDispatcher dispatcher) {
            logPrologue("ws onStart");
            self.dispatcher = dispatcher;

            // Send actor-model messages for incoming WS messages
            // received before this actor was started. FIXME: This
            // case ought not to exist.
            while (self.incoming.size() > 0) {
                self.dispatcher.tell(self, self.incoming.remove(0), self.originator);
            }
        }

        void onMessage(Actor origin, Object message) {
            logPrologue("ws onMessage (actor message)");
            logTS("   message is from " + origin.toString());
            if (message.getClass().id == "quark.String"
                && self.state == "CONNECTED") {
                logTS("   send-ish, message is: " + message.toString());
                self.socket.send(?message);
                return;
            }
            if (message.getClass().id == "mdk_runtime.WSClose"
                && self.state == "CONNECTED") {
                logTS("   close-ish, switching to DISCONNECTING state");
                self.state = "DISCONNECTING";
                self.socket.close();
                return;
            }
            logger.warn("ws onMessage got unhandled message: " +
                        message.getClass().id + " in state " + self.state);
        }

        // WSHandler
        void onWSConnected(WebSocket socket) {
            logPrologue("onWSConnected");
            if (self.state == "ERROR") {
                logTS("Connection event after error event!");
                return;
            }
            self.state = "CONNECTED";
            self.socket = socket;
            self.factory.resolve(self);
        }

        void onWSError(WebSocket socket, WSError error) {
            logPrologue("onWSError");
            logTS("onWSError, reason is: " + error.toString());
            if (self.state == "CONNECTING") {
                logger.error("Error connecting to WebSocket: " + error.toString());
                self.state = "ERROR";
                self.factory.reject(new WSConnectError(error.toString()));
                return;
            }
            logger.error("WebSocket error: " + error.toString());
        }

        void onWSMessage(WebSocket socket, String message) {
            logPrologue("onWSMessage");
            logTS("onWSMessage, message is: " + message);

            // FIXME: Sometimes we start receiving WS messages before
            // this actor has been started. Work around that for now
            // by buffering those WS messages and then delivering them
            // as actor messages in onStart(...).
            Object deliverable = new WSMessage(message);
            if (self.dispatcher == null) {
                self.incoming.add(deliverable);
            } else {
                self.dispatcher.tell(self, deliverable, self.originator);
            }
        }

        void onWSFinal(WebSocket socket) {
            logPrologue("onWSFinal");
            if (self.state == "DISCONNECTING" || self.state == "CONNECTED") {
                self.state = "DISCONNECTED";
                self.socket = null;

                // FIXME: Racy race race! See onWSMessage(...) above.
                Object deliverable = new WSClosed();
                if (self.dispatcher == null) {
                    self.incoming.add(deliverable);
                } else {
                    self.dispatcher.tell(self, deliverable, self.originator);
                }
            }
        }
    }

    @doc("""
    WebSocket that uses current Quark runtime as temporary expedient.
    """)
    class QuarkRuntimeWebSockets extends WebSockets {
        // XXX need better story for logging; perhaps integrate MDK Session with
        // the MessageDispatcher?
        Logger logger = new Logger("protocol");

        MessageDispatcher dispatcher;
        List<WSActor> connections = [];

        mdk_runtime.promise.Promise connect(String url, Actor originator) {
            logger.debug(originator.toString() + "requested connection to "
                         + url);
            PromiseResolver factory =  new PromiseResolver(self.dispatcher);
            QuarkRuntimeWSActor actor = new QuarkRuntimeWSActor(originator, factory);
            connections.add(actor);
            self.dispatcher.startActor(actor);
            Context.runtime().open(url, actor);
            return factory.promise;
        }

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object message) {}

        void onStop() {
            int idx = 0;
            while (idx < connections.size()) {
                self.dispatcher.tell(self, new WSClose(), self.connections[idx]);
                idx = idx + 1;
            }
        }
    }

    @doc("WSActor implementation for testing purposes.")
    class FakeWSActor extends WSActor {
        String url;
        PromiseResolver resolver;
        bool resolved = false;
        MessageDispatcher dispatcher;
        Actor originator;
        List<String> sent = [];
        String state = "CONNECTING";
        int expectIdx = 0;

        FakeWSActor(Actor originator, PromiseResolver resolver, String url) {
            self.url = url;
            self.originator = originator;
            self.resolver = resolver;
        }

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object message) {
            if (message.getClass().id == "quark.String"
                && self.state == "CONNECTED") {
                self.sent.add(?message);
                return;
            }
            if (message.getClass().id == "mdk_runtime.WSClose"
                && self.state == "CONNECTED") {
                self.close();
                return;
            }
        }

        // Testing API:
        @doc("""
        Simulate the remote peer accepting the socket connect.
        """)
        void accept() {
            if (resolved) {
                Context.runtime().fail("Test bug. already accepted");
            } else {
                resolved = true;
                self.state = "CONNECTED";
                self.resolver.resolve(self);
            }
        }

        @doc("Simulate the remote peer rejecting the socket connect.")
        void reject() {
            if (resolved) {
                Context.runtime().fail("Test bug. already accepted");
            } else {
                resolved = true;
                self.resolver.reject(new WSConnectError("connection refused"));
            }
        }

        @doc("""
        Simulate the remote peer sending a text message to the client.
        """)
        void send(String message) {
            if (self.state != "CONNECTED") {
                Context.runtime().fail("Test bug. Can't send when not connected.");
            }
            self.dispatcher.tell(self, new WSMessage(message), originator);
        }

        @doc("""
        Simulate the remote peer closing the socket.
        """)
        void close() {
            if (self.state == "CONNECTED") {
                self.state = "DISCONNECTED";
                self.dispatcher.tell(self, new WSClosed(), originator);
            } else {
                Context.runtime().fail("Test bug. Can't close already closed socket.");
            }
        }

        @doc("""
        Check that a message has been sent via this actor.
        """)
        String expectTextMessage() {
            if (!resolved) {
                Context.runtime().fail("not connected yet");
                return "unreachable";
            }

            if (expectIdx < self.sent.size()) {
                String msg = self.sent[expectIdx];
                expectIdx = expectIdx + 1;
                return msg;
            }
            Context.runtime().fail("no remaining message found");
            return "unreachable";
        }
    }

    @doc("""
    WebSocket implementation for testing purposes.
    """)
    class FakeWebSockets extends WebSockets {
        MessageDispatcher dispatcher;
        List<FakeWSActor> fakeActors = [];

        mdk_runtime.promise.Promise connect(String url, Actor originator) {
            PromiseResolver factory =  new PromiseResolver(self.dispatcher);
            FakeWSActor actor = new FakeWSActor(originator, factory, url);
            self.dispatcher.startActor(actor);
            self.fakeActors.add(actor);
            return factory.promise;
        }

        FakeWSActor lastConnection() {
            return self.fakeActors[self.fakeActors.size() - 1];
        }

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object message) {}
    }

    @doc("""
    Please send me a Happening message with given event name in given number of
    seconds.
    """)
    class Schedule {
        String event;
        float seconds;

        Schedule(String event, float seconds) {
            self.event = event;
            self.seconds = seconds;
        }
    }

    @doc("A scheduled event is now happening.")
    class Happening {
        String event;
        float currentTime;

        Happening(String event, float currentTime) {
            self.event = event;
            self.currentTime = currentTime;
        }
    }

    class _ScheduleTask extends Task {
        QuarkRuntimeTime timeService;
        Actor requester;
        String event;

        _ScheduleTask(QuarkRuntimeTime timeService, Actor requester, String event) {
            self.timeService = timeService;
            self.requester = requester;
            self.event = event;
        }

        void onExecute(Runtime runtime) {
            timeService.dispatcher.tell(
                self.timeService, new Happening(self.event, self.timeService.time()), self.requester);
        }
    }

    @doc("""
    Temporary implementation based on Quark runtime, until we have native
    implementation.
    """)
    class QuarkRuntimeTime extends Time, SchedulingActor {
        MessageDispatcher dispatcher;
        bool stopped = false;

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onStop() {
            self.stopped = true;
        }

        void onMessage(Actor origin, Object msg) {
            if (self.stopped) {
                return;
            }
            Schedule sched = ?msg;
            float seconds = sched.seconds;
            if (seconds == 0.0) {
                // Reduce chances of reentrant scheduled event; shouldn't be
                // necessary in non-threaded versions.
                seconds = 0.001;
            }
            Context.runtime().schedule(new _ScheduleTask(self, origin, sched.event), seconds);
        }

        float time() {
            float milliseconds = Context.runtime().now().toFloat();
            return milliseconds / 1000.0;
        }
    }

    class _FakeTimeRequest {
        Actor requester;
        String event;
        float happensAt;

        _FakeTimeRequest(Actor requester, String event, float happensAt) {
            self.requester = requester;
            self.event = event;
            self.happensAt = happensAt;
        }
    }

    @doc("Testing fake.")
    class FakeTime extends Time, SchedulingActor {
        float _now = 1000.0;
        Map<long,_FakeTimeRequest> _scheduled = {};
        MessageDispatcher dispatcher;

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object msg) {
            Schedule sched = ?msg;
            _scheduled[_scheduled.keys().size()] = new _FakeTimeRequest(origin, sched.event, self._now + sched.seconds);
        }

        float time() {
            return self._now;
        }

        @doc("Run scheduled events whose time has come.")
        void pump() {
            int idx = 0;
            List<long> keys = self._scheduled.keys();
            while (idx < keys.size()) {
                _FakeTimeRequest request = _scheduled[keys[idx]];
                if (request.happensAt <= self._now) {
                    self._scheduled.remove(keys[idx]);
                    self.dispatcher.tell(self, new Happening(request.event, time()), request.requester);
                }
                idx = idx + 1;
            }
        }

        @doc("Move time forward.")
        void advance(float seconds) {
            self._now = self._now + seconds;
        }

        @doc("Number of scheduled events.")
        int scheduled() {
            return self._scheduled.keys().size();
        }
    }

    @doc("EnvironmentVariable is a Supplier of Strings that come from the environment.")
    class EnvironmentVariable {
        String variableName;
        String _value;

        EnvironmentVariable(String variableName, String value) {
            self.variableName = variableName;
            self._value = value;
        }

        bool isDefined() {
            return get() != null;
        }

        String get() {
            return self._value;
        }

        String orElseGet(String alternative) {
            String result = get();
            if (result != null) {
                return result;
            }
            else {
                return alternative;
            }
        }
    }

    @doc("Inspect process environment variables.")
    interface EnvironmentVariables {
        @doc("Return an EnvironmentVariable instance for the given var.")
        EnvironmentVariable var(String name);
    }

    @doc("Use real environment variables.")
    class RealEnvVars extends EnvironmentVariables {
        EnvironmentVariable var(String name) {
            return new EnvironmentVariable(name,
                                           Environment.getEnvironment()[name]);
        }
    }

    @doc("Testing fake for EnvironmentVariables.")
    class FakeEnvVars extends EnvironmentVariables {
        Map<String,String> env = {};

        void set(String name, String value) {
            self.env[name] = value;
        }

        EnvironmentVariable var(String name) {
            String value = null;
            if (self.env.contains(name)) {
                value = self.env[name];
            }
            return new EnvironmentVariable(name, value);
        }
    }

    @doc("Create a MDKRuntime with the default configuration and start its actors.")
    MDKRuntime defaultRuntime() {
        MDKRuntime runtime = new MDKRuntime();
        runtime.dependencies.registerService("envvar", new RealEnvVars());
        QuarkRuntimeTime timeService = new QuarkRuntimeTime();
        QuarkRuntimeWebSockets websockets = new QuarkRuntimeWebSockets();
        runtime.dependencies.registerService("time", timeService);
        runtime.dependencies.registerService("schedule", timeService);
        runtime.dependencies.registerService("websockets", websockets);
        mdk_runtime.files.FileActor fileActor = new mdk_runtime.files.FileActorImpl(runtime);
        runtime.dependencies.registerService("files", fileActor);
        runtime.dispatcher.startActor(timeService);
        runtime.dispatcher.startActor(websockets);
        runtime.dispatcher.startActor(fileActor);
        return runtime;
    }

    MDKRuntime fakeRuntime() {
        MDKRuntime runtime = new MDKRuntime();
        runtime.dependencies.registerService("envvar", new FakeEnvVars());
        FakeTime timeService = new FakeTime();
        FakeWebSockets websockets = new FakeWebSockets();
        runtime.dependencies.registerService("time", timeService);
        runtime.dependencies.registerService("schedule", timeService);
        runtime.dependencies.registerService("websockets", websockets);
        mdk_runtime.files.FileActor fileActor = new mdk_runtime.files.FileActorImpl(runtime);
        runtime.dependencies.registerService("files", fileActor);
        runtime.dispatcher.startActor(timeService);
        runtime.dispatcher.startActor(websockets);
        runtime.dispatcher.startActor(fileActor);
        return runtime;
    }

}
