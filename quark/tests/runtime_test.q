quark 1.0;

/*
Tests for the MDK runtime.

We write these in Quark because each language will have its own runtime, so we
want as a first pass to just have one test suite. There may be additional tests
in target languages as needed.
*/

use ../mdk_runtime.q;
use ../actors.q;

import mdk_runtime;
import actors.core;


class RealSleep extends UnaryCallable {
    Object call(Object seconds) {
	// Don't actually have to do anything, time passes on its own.
	return true;
    }
}

class FakeSleep extends UnaryCallable {
    FakeTime fakeTime;

    FakeSleep(FakeTime time) {
	self.fakeTime = time;
    }

    Object call(Object seconds) {
	self.fakeTime.advance(?seconds);
	self.fakeTime.pump();
	return true;
    }
}

class Start {
    Actor testRunner;

    Start(Actor testRunner) {
	self.testRunner = testRunner;
    }
}

@doc("Tests for Time and Schedule services.")
class TimeScheduleTest extends Actor {
    Actor runner;
    Time timeService;
    Actor schedulingService;
    UnaryCallable sleepCallable;
    MessageDispatcher dispatcher;
    float startTime;

    TimeScheduleTest(Time time, Actor scheduling, UnaryCallable sleepCallable) {
	self.timeService = time;
	self.schedulingService = scheduling;
	self.sleepCallable = sleepCallable;
    }

    void onStart(MessageDispatcher dispatcher) {
	self.dispatcher = dispatcher;
    }

    void assertElapsed(float expected, float reportedTime) {
	float elapsed = reportedTime - self.startTime;
	print("Expected: " + expected.toString() + " elapsed: " + elapsed.toString());
	if (elapsed - expected > 0.1 || elapsed - expected < -0.1) {
	    Context.runtime().fail("Scheduled for too long!");
	}
    }

    void onMessage(Actor origin, Object message) {
	print(origin);
	print(message);
	if (message.getClass().id == "runtime_test.Start") {
	    Start start = ?message;
	    self.runner = start.testRunner;
	    self.startTime = self.timeService.time();
	    self.dispatcher.tell(self, new Schedule("1second", 1.0),
				 self.schedulingService);
	    self.dispatcher.tell(self, new Schedule("5second", 5.0),
				 self.schedulingService);
	    self.sleepCallable.__call__(1.0);
	    return;
	}

	Happening happened = ?message;
	if (happened.event == "1second") {
	    self.assertElapsed(1.0, happened.currentTime);
	    self.assertElapsed(1.0, self.timeService.time());
	    self.sleepCallable.__call__(4.0); // Should hit 5 seconds
	    return;
	}
	if (happened.event == "5second") {
	    self.assertElapsed(5.0, happened.currentTime);
	    self.assertElapsed(5.0, self.timeService.time());
	    self.dispatcher.tell(self, "next", self.runner);
	}
    }
}

@doc("""
Run a series of actor-based tests. Receiving \"next\" triggers next test.
""")
class TestRunner extends Actor {
    Map<String,Actor> tests;
    List<String> testNames;
    int nextTest = 0;
    MessageDispatcher dispatcher;

    TestRunner(Map<String,Actor> tests) {
	self.tests = tests;
	self.testNames = tests.keys();
    }

    void onStart(MessageDispatcher dispatcher) {
	self.dispatcher = dispatcher;
	dispatcher.tell(self, "next", self);
    }

    void onMessage(Actor origin, Object msg) {
	if (self.nextTest > 0) {
	    print("Test done successfully.\n");
	}
	if (self.nextTest == testNames.size()) {
	    print("All done.");
	    return;
	}
	String testName = self.testNames[self.nextTest];
	print("Running " + testName);
	self.dispatcher.startActor(self.tests[testName]);
	self.dispatcher.tell(self, new Start(self), self.tests[testName]);
	self.nextTest = self.nextTest + 1;
    }
}

void main(List<String> args) {
    MDKRuntime runtime = defaultRuntime();
    Actor realTimeTest = new TimeScheduleTest(runtime.getTimeService(),
					      runtime.getScheduleService(),
					      new RealSleep());
    FakeTime fakeTime = new FakeTime();
    Actor fakeTimeTest = new TimeScheduleTest(fakeTime, fakeTime,
					      new FakeSleep(fakeTime));
    Actor runner = new TestRunner({"Real runtime: time, scheduling": realTimeTest,
				   "Fake runtime: time, Scheduling": fakeTimeTest});
    runtime.dispatcher.startActor(runner);
}
