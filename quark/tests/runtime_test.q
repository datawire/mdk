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


@doc("""
An Actor that runs some tests.

start() is called to start the test, and it should be called *not* via the
MessageDispatcher mechanism. This means code run by start() can assume it is
'top of the call stack'.

(Technically it might not be, but there's a new MessageDispatcher for every test
so for purposes of message delivery it is.)
""")
interface TestActor extends Actor {
    @doc("Start the test. Should not be in current MessageDispatcher.")
    void start(TestRunner runner);
}

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

class Sleep {
    float seconds;

    Sleep(float seconds) {
	self.seconds = seconds;
    }
}

@doc("Tests for Time and Schedule services.")
class TimeScheduleTest extends TestActor {
    TestRunner runner;
    Time timeService;
    Actor schedulingService;
    UnaryCallable sleepCallable;
    MessageDispatcher dispatcher;
    float startTime;
    bool scheduling = false;

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
	print("Expected: " + expected.toString() + " delay, actually elapsed: " + elapsed.toString());
	if (elapsed - expected > 0.1 || elapsed - expected < -0.1) {
	    Context.runtime().fail("Scheduled for too long!");
	}
    }

    void start(TestRunner runner) {
        self.runner = runner;
        self.startTime = self.timeService.time();
        // Set a bool that will allow us to test for reentrancy.
        self.scheduling = true;
        self.dispatcher.tell(self, new Schedule("0second", 0.0),
                             self.schedulingService);
        self.scheduling = false;
        self.dispatcher.tell(self, new Schedule("1second", 1.0),
                             self.schedulingService);
        self.dispatcher.tell(self, new Schedule("5second", 5.0),
                             self.schedulingService);
        self.dispatcher.tell(self, new Sleep(0.0), self);
    }

    void onMessage(Actor origin, Object message) {
	if (message.getClass().id == "runtime_test.Sleep") {
	    Sleep sleep = ?message;
	    self.sleepCallable.__call__(sleep.seconds);
	    return;
	}

	Happening happened = ?message;
        if (happened.event == "0second") {
            print("0 second event delivered.");
            if (self.scheduling) {
                Context.runtime().fail("Scheduled event reentrantly!");
            }
            // Sleep 1 second to hit 1second scheduled event:
            self.dispatcher.tell(self, new Sleep(1.0), self);
            return;
        }
	if (happened.event == "1second") {
            print("1 second event delivered.");
	    self.assertElapsed(1.0, happened.currentTime);
	    self.assertElapsed(1.0, self.timeService.time());
	    // Already slept 1 seconds, now sleep 4 to hit 5 seconds:
	    self.dispatcher.tell(self, new Sleep(4.0), self);
	    return;
	}
	if (happened.event == "5second") {
            print("5 second event delivered.");
	    self.assertElapsed(5.0, happened.currentTime);
	    self.assertElapsed(5.0, self.timeService.time());
            self.runner.runNextTest();
	}
    }
}

@doc("""
Make sure we don't exit prematurely due to buggy tests.

Times out after 60 seconds.

Stops keep-alive scheduling if a \"stop\" message is received.
""")
class KeepaliveActor extends Actor {
    MDKRuntime runtime;
    float timeStarted;
    bool stopped;

    KeepaliveActor(MDKRuntime runtime) {
	self.runtime = runtime;
	self.stopped = false;
    }

    void onStart(MessageDispatcher tell) {
	self.timeStarted = self.runtime.getTimeService().time();
	self.onMessage(self, "go");
    }

    void onMessage(Actor origin, Object message) {
	if (message == "stop") {
	    self.stopped = true;
	    return;
	}
	// Must be a Happening message from the scheduling service:
	if (self.stopped) {
	    return;
	}
	if (self.runtime.getTimeService().time() - self.timeStarted > 60.0) {
	    Context.runtime().fail("Tests took too long.");
	    return;
	}
	self.runtime.dispatcher.tell(self, new Schedule("wakeup", 1.0),
				     self.runtime.getScheduleService());
    }
}

@doc("""
Run a series of actor-based tests. Receiving \"next\" triggers next test.

Deliberately not an Actor so MessageDispatcher doesn't get affected by it and
hide e.g. reentrancy issues in scheduling.
""")
class TestRunner {
    Map<String,UnaryCallable> tests;
    List<String> testNames;
    int nextTest = 0;
    MDKRuntime runtime;
    KeepaliveActor keepalive;

    TestRunner() {
	self.tests = {"real runtime: time, scheduling":
                      bind(self, "testRealRuntimeScheduling", []),
                      "fake runtime: time, scheduling":
                      bind(self, "testFakeRuntimeScheduling", [])};
	self.testNames = tests.keys();
    }

    TestActor testRealRuntimeScheduling(MDKRuntime runtime) {
        return new TimeScheduleTest(runtime.getTimeService(),
                                    runtime.getScheduleService(),
                                    new RealSleep());
    }

    TestActor testFakeRuntimeScheduling(MDKRuntime runtime) {
        FakeTime fakeTime = new FakeTime();
        runtime.dispatcher.startActor(fakeTime);
        return new TimeScheduleTest(fakeTime, fakeTime, new FakeSleep(fakeTime));

    }

    void runNextTest() {
        // If we're not the first test, cleanup:
	if (self.nextTest > 0) {
	    self.runtime.dispatcher.tell(null, "stop", self.keepalive);
	    print("Test finished successfully.\n");
	}

        // If there are no more tests we're done:
	if (self.nextTest == testNames.size()) {
	    print("All done.");
	    return;
	}

        // Setup new runtime for a new test:
        self.runtime = defaultRuntime();

        // Don't exit if we run out of events somehow, but do exit if we hit a
	// timeout:
	self.keepalive = new KeepaliveActor(self.runtime);
	self.runtime.dispatcher.startActor(keepalive);

        // Run the next test:
	String testName = self.testNames[self.nextTest];
	print("Testing " + testName);
        TestActor test = ?self.tests[testName].__call__(self.runtime);
        self.runtime.dispatcher.startActor(test);
        self.nextTest = self.nextTest + 1;
        test.start(self);
    }
}

void main(List<String> args) {
    new TestRunner().runNextTest();
}
