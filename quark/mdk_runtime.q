quark 1.0;

import actors;

namespace mdk_runtime {
    @doc("""\
    Handle time and scheduling.

    This should be an Actor that accepts Schedule messages and creates Happening
    events at appropriate time.
    """)
    interface Time {
	@doc("""\
        Return the current time in seconds since the Unix epoch.
        """)
	float time();
    }

    @doc("""\
    Please send me a Happening message with given event name in given number of
    milliseconds.
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

    class _ScheduleTask implements Task {
	ActorRef timeActor;
	ActorRef requester;
	String event;

	_ScheduleTask(ActorRef timeActor, ActorRef requester, String event) {
	    self.timeActor = timeActor;
	    self.requester = requester;
	    self.event = event;
	}

	void onExecute(Runtime runtime) {
	    QuarkRuntimeTime time = ?self.timeActor.getActor();
	    self.requester.tell(self.timeActor, new Happening(self.event, time.time()));
	}
    }

    @doc("""\
    Temporary implementation based on Quark runtime, until we have native
    implementation.
    """)
    class QuarkRuntimeTime implements Time, Actor {
	void onMessage(ActorRef selfRef, ActorRef origin, Message msg) {
	    Schedule sched = ?msg;
	    Context.runtime().schedule(new _ScheduleTask(selfRef, origin, sched.event), sched.seconds);
	}

	Message onAsk(ActorRef selfRef, ActorRef origin, Message msg) {
	    return new Unhandled();
	}

	float time() {
	    return Context.runtime().now() / 1000.0;
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
    class FakeTime implements Time, Actor {
	float _now = 1000.0;
	Map<long,_FakeTimeRequest> _scheduled = [];
	ActorRef selfRef;

	void onMessage(ActorRef selfRef, ActorRef origin, Message msg) {
	    self.selfRef = selfRef;
	    Schedule sched = ?msg;
	    _scheduled[_scheduled.size()] = new _FakeTimeRequest(origin, sched.event, self._now + sched.seconds);
	}

	Message onAsk(ActorRef selfRef, ActorRef origin, Message msg) {
	    return new Unhandled();
	}

	float time() {
	    return self._now;
	}

	@doc("Move time forward.")
	void advance(float seconds) {
	    self._now = self._now + seconds;
	    long idx = 0l;
	    List<long> keys = self._scheduled.keys();
	    while (idx < keys.size()) {
		_FakeTimeRequest request = scheduled[keys[idx]];
		if (request.happensAt <= self._now) {
		    self._scheduled.remove(keys[idx]);
		    request.requester.tell(self.selfRef, new Happening(request.event, time()));
		}
		idx = idx + 1;
	    }
	}
    }
}
