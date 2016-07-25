quark 1.0;

use actors.q;
import actors;

namespace mdk_runtime {
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
    Please send me a Happening message with given event name in given number of
    milliseconds.
    """)
    class Schedule extends Message {
	String event;
	float seconds;

	Schedule(String event, float seconds) {
	    self.event = event;
	    self.seconds = seconds;
	}
    }

    @doc("A scheduled event is now happening.")
    class Happening extends Message {
	String event;
	float currentTime;

	Happening(String event, float currentTime) {
	    self.event = event;
	    self.currentTime = currentTime;
	}
    }

    class _ScheduleTask extends Task {
	QuarkRuntimeTime timeService;
	ActorRef requester;
	String event;

	_ScheduleTask(QuarkRuntimeTime timeService, ActorRef requester, String event) {
	    self.timeService = timeService;
	    self.requester = requester;
	    self.event = event;
	}

	void onExecute(Runtime runtime) {
	    self.requester.tell(self.timeService, new Happening(self.event, self.timeService.time()));
	}
    }

    @doc("""
    Temporary implementation based on Quark runtime, until we have native
    implementation.
    """)
    class QuarkRuntimeTime extends Time, SchedulingActor {
	void onMessage(ActorRef origin, Message msg) {
	    Schedule sched = ?msg;
	    Context.runtime().schedule(new _ScheduleTask(self, origin, sched.event), sched.seconds);
	}

	Message onAsk(ActorRef origin, Message msg) {
	    return new Unhandled();
	}

	float time() {
	    float milliseconds = ?Context.runtime().now();
	    return milliseconds / 1000.0;
	}
    }

    class _FakeTimeRequest {
	ActorRef requester;
	String event;
	float happensAt;

	_FakeTimeRequest(ActorRef requester, String event, float happensAt) {
	    self.requester = requester;
	    self.event = event;
	    self.happensAt = happensAt;
	}
    }

    @doc("Testing fake.")
    class FakeTime extends Time, SchedulingActor {
	float _now = 1000.0;
	Map<long,_FakeTimeRequest> _scheduled = {};

	void onMessage(ActorRef origin, Message msg) {
	    Schedule sched = ?msg;
	    _scheduled[_scheduled.keys().size()] = new _FakeTimeRequest(origin, sched.event, self._now + sched.seconds);
	}

	Message onAsk(ActorRef origin, Message msg) {
	    return new Unhandled();
	}

	float time() {
	    return self._now;
	}

	@doc("Move time forward.")
	void advance(float seconds) {
	    self._now = self._now + seconds;
	    long idx = 0;
	    List<long> keys = self._scheduled.keys();
	    while (idx < keys.size()) {
		_FakeTimeRequest request = _scheduled[keys[idx]];
		if (request.happensAt <= self._now) {
		    self._scheduled.remove(keys[idx]);
		    request.requester.tell(self, new Happening(request.event, time()));
		}
		idx = idx + 1;
	    }
	}
    }
}
