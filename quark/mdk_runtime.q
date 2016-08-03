quark 1.0;

use actors.q;
use dependency.q;
import actors.core;
import dependency;

namespace mdk_runtime {
    @doc("""
    Runtime environment for a particular MDK instance.

    Required registered services:
    - 'time': A provider of mdk_runtime.Time;
    - 'schedule': Implements the mdk_runtime.ScheduleActor actor protocol.
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
	@doc("The Promise resolves to a WSActor or WSConnectError. The destination will receive messages.")
	Promise connect(String url, Actor destination);
    }

    @doc("Connection failed.")
    class WSConnectError extends Error {}

    @doc("""
    Actor representing a specific WebSocket connection.

    Accepts String and WSClose messages, sends String and WSClosed
    messages to the originator of the connection (Actor passed to
    WebSockets.connect()).
    """)
    interface WSActor extends Actor {}

    @doc("Tell WSActor to close the connection.")
    class WSClose() {}

    @doc("Notify of WebSocket connection having closed.")
    class WSClosed() {}

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
	    Context.runtime().schedule(new _ScheduleTask(self, origin, sched.event), sched.seconds);
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
    }

    @doc("Create a MDKRuntime with the default configuration.")
    MDKRuntime defaultRuntime() {
	MDKRuntime runtime = new MDKRuntime();
        QuarkRuntimeTime timeService = new QuarkRuntimeTime();
        runtime.dependencies.registerService("time", timeService);
        runtime.dependencies.registerService("schedule", timeService);
	runtime.dispatcher.startActor(timeService);
	return runtime;
    }
}
