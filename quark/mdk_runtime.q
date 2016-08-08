quark 1.0;

package datawire_mdk_runtime 1.0.0;

use actors.q;
use dependency.q;
import actors.core;
import actors.promise;
import dependency;

namespace mdk_runtime {
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
    """)
    interface WebSockets {
	@doc("""
        The Promise resolves to a WSActor or WSConnectError. The originator will
        receive messages.
        """)
	actors.promise.Promise connect(String url, Actor originator);
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
	static Logger logger = new Logger("protocol");
	WebSocket socket;
	PromiseResolver factory;
	Actor originator;
	MessageDispatcher dispatcher;
	String state = "CONNECTING";

	QuarkRuntimeWSActor(Actor originator, PromiseResolver factory) {
	    self.originator = originator;
	    self.factory = factory;
	}

	// Actor
	void onStart(MessageDispatcher dispatcher) {
	    self.dispatcher = dispatcher;
	}

	void onMessage(Actor origin, Object message) {
	    if (message.getClass().id == "quark.String"
		&& self.state == "CONNECTED") {
		self.socket.send(?message);
		return;
	    }
	    if (message.getClass().id == "mdk_runtime.WSClose"
		&& self.state == "CONNECTED") {
		self.state = "DISCONNECTING";
		self.socket.close();
		return;
	    }
	}

	// WSHandler
	void onWSConnected(WebSocket socket) {
	    logger.debug("onWSConnected, current state " + self.state +
			 "originator: " + self.originator.toString() + " and I am " +
			 self.toString());
	    if (self.state == "ERROR") {
		logger.debug("Connection event after error event!");
		return;
	    }
	    self.state = "CONNECTED";
	    self.socket = socket;
	    self.factory.resolve(self);
	}

	void onWSError(WebSocket socket, WSError error) {
	    logger.debug("onWSError, current state " + self.state +
			 "originator: " + self.originator.toString());
	    if (self.state == "CONNECTING") {
		logger.error("Error connecting to WebSocket: " + error.toString());
                self.state = "ERROR";
		self.factory.reject(new WSConnectError(error.toString()));
		return;
	    }
	    logger.error("WebSocket error: " + error.toString());
	}

	void onWSMessage(WebSocket socket, String message) {
	    logger.debug("onWSMessage, current state: " + self.state +
			 "originator: " + self.originator.toString());
	    self.dispatcher.tell(self, new WSMessage(message), self.originator);
	}

	void onWSFinal(WebSocket socket) {
	    logger.debug("onWSFinal, current state " + self.state +
			 "originator: " + self.originator.toString());
	    if (self.state == "DISCONNECTING" || self.state == "CONNECTED") {
		self.state = "DISCONNECTED";
		self.socket = null;
		self.dispatcher.tell(self, new WSClosed(), self.originator);
	    }
	}
    }

    @doc("""
    WebSocket that uses current Quark runtime as temporary expedient.
    """)
    class QuarkRuntimeWebSockets extends WebSockets {
	// XXX need better story for logging; perhaps integrate MDK Session with
	// the MessageDispatcher?
	static Logger logger = new Logger("protocol");

	MessageDispatcher dispatcher;

	QuarkRuntimeWebSockets(MessageDispatcher dispatcher) {
	    self.dispatcher = dispatcher;
	}

	actors.promise.Promise connect(String url, Actor originator) {
	    logger.debug(originator.toString() + "requested connection to "
			 + url);
	    PromiseResolver factory =  new PromiseResolver(self.dispatcher);
	    QuarkRuntimeWSActor actor = new QuarkRuntimeWSActor(originator, factory);
	    self.dispatcher.startActor(actor);
	    Context.runtime().open(url, actor);
	    return factory.promise;
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

	FakeWebSockets(MessageDispatcher dispatcher) {
	    self.dispatcher = dispatcher;
	}

        actors.promise.Promise connect(String url, Actor originator) {
            PromiseResolver factory =  new PromiseResolver(self.dispatcher);
	    FakeWSActor actor = new FakeWSActor(originator, factory, url);
	    self.dispatcher.startActor(actor);
            self.fakeActors.add(actor);
	    return factory.promise;
	}

        FakeWSActor lastConnection() {
            return self.fakeActors[self.fakeActors.size() - 1];
        }
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

	void onStart(MessageDispatcher dispatcher) {
	    self.dispatcher = dispatcher;
	}

	void onMessage(Actor origin, Object msg) {
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

    @doc("Create a MDKRuntime with the default configuration.")
    MDKRuntime defaultRuntime() {
	MDKRuntime runtime = new MDKRuntime();
        QuarkRuntimeTime timeService = new QuarkRuntimeTime();
        runtime.dependencies.registerService("time", timeService);
        runtime.dependencies.registerService("schedule", timeService);
	runtime.dependencies.registerService("websockets",
					     new QuarkRuntimeWebSockets(runtime.dispatcher));
	runtime.dispatcher.startActor(timeService);
	return runtime;
    }
}
