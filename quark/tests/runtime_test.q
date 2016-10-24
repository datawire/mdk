quark 1.0;

/*
Tests for the MDK runtime.

We write these in Quark because each language will have its own runtime, so we
want as a first pass to just have one test suite. There may be additional tests
in target languages as needed.
*/

use ../mdk_runtime.q;

import mdk_runtime;
import mdk_runtime.files;
import mdk_runtime.actors;
import mdk_runtime.promise;

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
Tests for the WebSockets service.

Takes two server URLS. The good one should act as an echo server, and close when
it receives 'close'. The bad one should just be a connection refused.
""")
class WebSocketsTest extends TestActor {
    TestRunner runner;
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

    void changeState(String state) {
	print("State: " + state);
	self.state = state;
    }

    bool _gotError(WSConnectError error) {
	self.testGoodURL();
	return true;
    }

    @doc("Bad URLs result in Promise rejected with WSError.")
    void testBadURL() {
	self.changeState("testBadURL");
	mdk_runtime.promise.Promise p = self.websockets.connect(badURL, self);
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
	self.changeState("testGoodURL");
	mdk_runtime.promise.Promise p = self.websockets.connect(serverURL, self);
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
	self.changeState("testMessages");
	self.dispatcher.tell(self, "can you hear me?", self.connection);
	// Response will go to _gotMessage.
    }

    void _gotClose() {
	self.testSendToClosed();
    }

    @doc("The connection can be closed.")
    void testClose() {
	self.changeState("testClose");
	self.dispatcher.tell(self, new WSClose(), self.connection);
	// Close will be delivered by calling _gotClose().
    }

    @doc("Send to closed socket is just dropped on the floor.")
    void testSendToClosed() {
	self.changeState("testSendToClosed");
	// These should not blow up, should instead just be dropped on the floor:
	self.dispatcher.tell(self, "goes nowhere", self.connection);
	self.dispatcher.tell(self, new WSClose(), self.connection);
	// All done, tell test runner to proceed.
        self.runner.runNextTest();
    }

    void start(TestRunner runner) {
        self.runner = runner;
        testBadURL();
    }

    void onMessage(Actor origin, Object message) {
	if (connection == null) {
	    panic("Got message while still unconnected.");
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
Tests for FileActor.
""")
class FileActorTests extends TestActor {
    FileActor actor;
    MessageDispatcher dispatcher;
    TestRunner runner;
    String state = "initial";
    String directory;
    String file;

    FileActorTests(FileActor actor) {
	self.actor = actor;
        self.directory = actor.mktempdir();
        self.file = self.directory + "/file1";
    }

    void changeState(String state) {
	print("State: " + state);
	self.state = state;
    }

    void onStart(MessageDispatcher dispatcher) {
        self.dispatcher = dispatcher;
        self.dispatcher.startActor(self.actor);
    }

    void start(TestRunner runner) {
        self.runner = runner;
        self.testCreateNotification();
    }

    void testCreateNotification() {
        self.changeState("testCreateNotification");
        self.dispatcher.tell(self, new SubscribeChanges(self.directory), self.actor);
        self.actor.write(self.file, "initial value");
    }

    void assertCreateNotification(FileContents contents) {
        if (contents.path != self.file || contents.contents != "initial value") {
            panic("Unexpected results: " + contents.path + " " + contents.contents);
        }
        self.testChangeNotification();
    }

    void testChangeNotification() {
        self.changeState("testChangeNotification");
        self.actor.write(self.file, "changed value");
    }

    void assertChangeNotification(FileContents contents) {
        if (contents.path == self.file) {
            if (contents.contents == "initial value") {
                // False positive hopefully just predating update, so continue
                return;
            }
            if (contents.contents != "changed value") {
                panic("Unexpected value: " + contents.contents);
            }
        } else {
            panic("Unexpected file: " + contents.path);
        }
        self.testDeleteNotification();
    }

    void testDeleteNotification() {
        self.changeState("testDeleteNotification");
        self.actor.delete(self.file);
    }

    void assertDeleteNotification(FileDeleted deleted) {
        if (deleted.path != self.file) {
            panic("Unexpected value: " + deleted.path);
        }
        self.state = "done";
        self.dispatcher.stopActor(self.actor);
        runner.runNextTest();
    }

    void onMessage(Actor origin, Object message) {
        String typeId = message.getClass().id;
        if (self.state == "testCreateNotification") {
            if (typeId != "mdk_runtime.files.FileContents") {
                panic("Unexpected message: " + typeId);
            }
            self.assertCreateNotification(?message);
            return;
        }
        if (self.state == "testChangeNotification") {
            if (typeId != "mdk_runtime.files.FileContents") {
                panic("Unexpected message: " + typeId);
            }
            self.assertChangeNotification(?message);
            return;
        }
        if (self.state == "testDeleteNotification") {
            if (typeId == "mdk_runtime.files.FileContents") {
                return; // hopefully just spurious false positive
            }
            if (typeId != "mdk_runtime.files.FileDeleted") {
                panic("Unexpected message: " + typeId);
            }
            self.assertDeleteNotification(?message);
            return;
        }
        panic("Unexpected message: " + message.toString());
    }
}

@doc("""
Make sure we don't exit prematurely due to buggy tests.

Times out after 60 seconds.
""")
class KeepaliveActor extends Actor {
    MDKRuntime runtime;
    float timeStarted;
    bool stopping = false;

    KeepaliveActor(MDKRuntime runtime) {
	self.runtime = runtime;
    }

    void onStart(MessageDispatcher tell) {
	self.timeStarted = self.runtime.getTimeService().time();
	self.onMessage(self, "go");
    }

    void onStop() {
        self.stopping = true;
    }

    void onMessage(Actor origin, Object message) {
        // Must be a Happening message from the scheduling service.
	if (self.stopping) {
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

@doc("Wrap FakeWebSockets into an echo server.")
class EchoFakeWSActor extends WSActor {
    FakeWSActor fake;

    EchoFakeWSActor(FakeWSActor fake) {
        self.fake = fake;
    }

    void onStart(MessageDispatcher dispatcher) {
        self.fake.onStart(dispatcher);
    }

    void onMessage(Actor originator, Object message) {
        self.fake.onMessage(originator, message);
        if (self.fake.state == "CONNECTED" && message.getClass().id == "quark.String") {
            // It's an echo server!
            self.fake.send(self.fake.expectTextMessage());
        }
    }
}

@doc("Extend FakeWebSockets with policy specific to the tests we're running.")
class TestPolicyFakeWebSockets extends WebSockets {
    FakeWebSockets fake;

    TestPolicyFakeWebSockets(MessageDispatcher dispatcher) {
        self.fake = new FakeWebSockets();
    }

    EchoFakeWSActor wrapFakeWSActor(FakeWSActor actor) {
        return new EchoFakeWSActor(actor);
    }

    mdk_runtime.promise.Promise connect(String url, Actor originator) {
        Promise result = self.fake.connect(url, originator);
        FakeWSActor actor = self.fake.lastConnection();
        if (url == "wss://echo/") {
            // Create an echo server:
            actor.accept();
            return result.andThen(bind(self, "wrapFakeWSActor", []));
        } else {
            // Connection refused!
            actor.reject();
        }
        return result;
    }

    void onStart(MessageDispatcher dispatcher) {
        self.fake.onStart(dispatcher);
    }

    void onStop() {
        self.fake.onStop();
    }

    void onMessage(Actor origin, Object message) {}
}

macro bool isPython() $py{True} $js{false} $java{false} $rb{false};

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
                      bind(self, "testFakeRuntimeScheduling", []),
                      "real runtime: websockets":
                      bind(self, "testRealRuntimeWebsockets", []),
                      "fake runtime: websockets":
                      bind(self, "testFakeRuntimeWebSockets", [])};
        // Not bothering with other languages in this iteration, will add them
        // later.
        if (isPython()) {
            self.tests["files"] = bind(self, "testFiles", []);
        }
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

    TestActor testRealRuntimeWebsockets(MDKRuntime runtime) {
        // XXX should really use local server, not server on Internet
        WebSocketsTest result = new WebSocketsTest(new QuarkRuntimeWebSockets(),
                                                   "ws://127.0.0.1:9123/", "wss://localhost:1/");
        runtime.dispatcher.startActor(result.websockets);
        return result;
    }

    TestActor testFakeRuntimeWebSockets(MDKRuntime runtime) {
        WebSocketsTest result = new WebSocketsTest(new TestPolicyFakeWebSockets(runtime.dispatcher),
                                                   "wss://echo/", "wss://bad/");
        runtime.dispatcher.startActor(result.websockets);
        return result;
    }

    TestActor testFiles(MDKRuntime runtime) {
        return new FileActorTests(new FileActorImpl(runtime));
    }

    void runNextTest() {
        // If we're not the first test, cleanup:
	if (self.nextTest > 0) {
	    self.runtime.dispatcher.stopActor(self.keepalive);
            self.runtime.stop();
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
