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

class Sleep {
    float seconds;

    Sleep(float seconds) {
	self.seconds = seconds;
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
	print("Expected: " + expected.toString() + " delay, actually elapsed: " + elapsed.toString());
	if (elapsed - expected > 0.1 || elapsed - expected < -0.1) {
	    Context.runtime().fail("Scheduled for too long!");
	}
    }

    void onMessage(Actor origin, Object message) {
	if (message.getClass().id == "runtime_test.Start") {
	    Start start = ?message;
	    self.runner = start.testRunner;
	    self.startTime = self.timeService.time();
	    self.dispatcher.tell(self, new Schedule("1second", 1.0),
				 self.schedulingService);
	    self.dispatcher.tell(self, new Schedule("5second", 5.0),
				 self.schedulingService);
	    self.dispatcher.tell(self, new Sleep(1.0), self);
	    return;
	}

	if (message.getClass().id == "runtime_test.Sleep") {
	    Sleep sleep = ?message;
	    self.sleepCallable.__call__(sleep.seconds);
	    return;
	}

	Happening happened = ?message;
	if (happened.event == "1second") {
	    self.assertElapsed(1.0, happened.currentTime);
	    self.assertElapsed(1.0, self.timeService.time());
	    // Already slept 1 seconds, now sleep 4 to hit 5 seconds:
	    self.dispatcher.tell(self, new Sleep(4.0), self);
	    return;
	}
	if (happened.event == "5second") {
	    self.assertElapsed(5.0, happened.currentTime);
	    self.assertElapsed(5.0, self.timeService.time());
	    // All done, tell test runner to proceed.
	    self.dispatcher.tell(self, "next", self.runner);
	}
    }
}

@doc("""
Tests for the WebSockets service.

Takes two server URLS. The good one should act as an echo server, and close when
it receives 'close'. The bad one should just be a connection refused.
""")
class WebSocketsTest extends Actor {
    Actor runner;
    WebSockets websockets;
    String serverURL;
    String badURL;
    MessageDispatcher dispatcher;
    WSActor connection;
    String state = "initial";

    WebSocketsTest(WebSockets websockets, String serverURL, String badURL) {
	self.websockets = websockets;
	self.serverURL = serverURL;
	self.badURL = badURL;
    }

    void onStart(MessageDispatcher dispatcher) {
	self.dispatcher = dispatcher;
    }

    void failure(Object result, String reason) {
	panic("WebSocket test failed: " + reason + " with " + result.toString());
    }

    bool _gotError(WSConnectError error) {
	self.testGoodURL();
	return true;
    }

    @doc("Bad URLs result in Promise rejected with WSError.")
    void testBadURL() {
	self.state = "testBadURL";
	Promise p = self.websockets.connect(badURL, self);
	p.andEither(bind(self, "failure", ["unexpected successful connection"]),
		    bind(self, "_gotError", []));
    }

    bool _gotWebSocket(WSActor actor) {
	self.connection = actor;
	testMessages();
	return true;
    }

    @doc("A good URL results in a Promise resolved with a WSActor.")
    void testGoodURL() {
	self.state = "testGoodURL";
	Promise p = self.websockets.connect(serverURL, self);
	p.andEither(bind(self, "_gotWebSocket", []),
		    bind(self, "failure", ["unexpected connect error"]));
    }

    void _gotMessage(String message) {
	if (message != "can you hear me?") {
	    panic("Unexpected echo message: " + message);
	}
	self.testClose();
    }

    @doc("Messages can be sent and received.")
    void testMessages() {
	self.state = "testMessages";
	self.dispatcher.tell(self, "can you hear me?", self.connection);
	// Response will go to _gotMessage.
    }

    void _gotClose() {
	// All done, tell test runner to proceed.
	self.dispatcher.tell(self, "next", self.runner);
    }

    @doc("The connection can be closed.")
    void testClose() {
	self.state = "testClose";
	self.dispatcher.tell(self, new WSClose(), self.connection);
	// Close will be delivered by calling _gotClose().
    }

    void onMessage(Actor origin, Object message) {
	if (message.getClass().id == "runtime_test.Start") {
	    Start start = ?message;
	    self.runner = start.testRunner;
	    testBadURL();
	    return;
	}
	if (connection == null) {
	    panic("Got message while still unconnected.");
	}
	if (origin != connection) {
	    panic("Got message from unexpected source: " + origin.toString());
	}
	if (message.getClass().id == "mdk_runtime.WSMessage" && self.state == "testMessages") {
	    WSMessage m = ?message;
	    self._gotMessage(m.body);
	    return;
	}
	if (message.getClass().id == "mdk_runtime.WSClosed" && self.state == "testClose") {
	    self._gotClose();
	    return;
	}
	panic("Unexpected message, state: " + self.state + " message: " + message.toString());
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
""")
class TestRunner extends Actor {
    Map<String,Actor> tests;
    List<String> testNames;
    int nextTest = 0;
    MDKRuntime runtime;
    KeepaliveActor keepalive;

    TestRunner(Map<String,Actor> tests, MDKRuntime runtime) {
	self.tests = tests;
	self.testNames = tests.keys();
	self.runtime = runtime;
    }

    void onStart(MessageDispatcher dispatcher) {
	// Don't exit  if we  run out of  events somehow,  but do exit  if we  hit a
	// timeout:
	self.keepalive = new KeepaliveActor(self.runtime);
	dispatcher.startActor(keepalive);
	self.runtime.dispatcher.tell(self, "next", self);
    }

    void onMessage(Actor origin, Object msg) {
	if (self.nextTest > 0) {
	    print("Test finished successfully.\n");
	}
	if (self.nextTest == testNames.size()) {
	    print("All done.");
	    // Shut down the keep-alive actor:
	    self.runtime.dispatcher.tell(self, "stop", self.keepalive);
	    return;
	}
	String testName = self.testNames[self.nextTest];
	print("Testing " + testName);
	self.runtime.dispatcher.startActor(self.tests[testName]);
	self.runtime.dispatcher.tell(self, new Start(self), self.tests[testName]);
	self.nextTest = self.nextTest + 1;
    }
}

void main(List<String> args) {
    MDKRuntime runtime = defaultRuntime();
    Actor realTimeTest = new TimeScheduleTest(runtime.getTimeService(),
					      runtime.getScheduleService(),
					      new RealSleep());
    FakeTime fakeTime = new FakeTime();
    runtime.dispatcher.startActor(fakeTime);
    Actor fakeTimeTest = new TimeScheduleTest(fakeTime, fakeTime,
					      new FakeSleep(fakeTime));
    Actor realWebSockets = new WebSocketsTest(new QuarkRuntimeWebSockets(runtime.dispatcher),
					     "wss://echo.websocket.org/", "wss://localhost:1/");
    Actor runner = new TestRunner({"real runtime: time, scheduling": realTimeTest,
				   "fake runtime: time, scheduling": fakeTimeTest,
				   "real runtime: websockets": realWebSockets
	                          },
	                          runtime);
    runtime.dispatcher.startActor(runner);
}
