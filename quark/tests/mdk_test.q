quark 1.0;

/* There are more tests in tests/test_*.py. */

include ../mdk-2.0.q;

package datawire_mdk_test 1.0.0;

import quark.test;
import quark.reflect;

import mdk_tracing;
import mdk_tracing.protocol;
import mdk_runtime;
import mdk_discovery;
import mdk_rtp;

void main(List<String> args) {
    logging.makeConfig().setLevel("DEBUG").configure();
    test.run(args);
}

FakeWSActor expectSocket(MDKRuntime runtime, String url) {
    FakeWebSockets ws = ?runtime.getWebSocketsService();
    FakeWSActor actor = ws.lastConnection();
    // May or may not have token appended depending on env variables...
    if (!actor.url.startsWith(url)) {
        checkEqual(url, actor.url);
        return null;
    } else {
        return actor;
    }
}

Serializable expectSerializable(FakeWSActor sev, String expectedType) {
    String msg = sev.expectTextMessage();
    if (msg == null) {
        check(false, "No message sent.");
        return null;
    }
    Object evt = Serializable.decodeClassName(expectedType, msg);
    String type = evt.getClass().getName();
    if (check(type == expectedType, "expected " + expectedType + " event, got " + type)) {
        return ?evt;
    } else {
        return null;
    }
}

class TracingTest {
    MDKRuntime runtime;
    OperationalEnvironment SANDBOX = new OperationalEnvironment();

    TracingTest() {
        self.runtime = fakeRuntime();
        FakeEnvVars env = ?self.runtime.getEnvVarsService();
        env.set("DATAWIRE_TOKEN", "");
    }

    void pump() {
        FakeTime timeService = ?runtime.getTimeService();
        timeService.pump();
    }

    /////////////////
    // Helpers
    Open expectOpen(FakeWSActor evt) {
        return ?expectSerializable(evt, "mdk_protocol.Open");
    }

    LogEvent expectLogEvent(FakeWSActor evt) {
        return ?expectSerializable(evt, "mdk_tracing.protocol.LogEvent");
    }

    Subscribe expectSubscribe(FakeWSActor evt) {
        return ?expectSerializable(evt, "mdk_tracing.protocol.Subscribe");
    }

    /////////////////
    // Tests

    void testLogCustomURL() {
        doTestLog("custom");
    }

    Tracer newTracer(String url) {
        WSClient client = new WSClient(runtime, getRTPParser(), url, "the_token");
        OpenCloseSubscriber openclose = new OpenCloseSubscriber(client, "abc", SANDBOX);
        runtime.dispatcher.startActor(openclose);
        return new Tracer(runtime, client);
    }

    FakeWSActor startTracer(Tracer tracer) {
        runtime.dispatcher.startActor(tracer._client._wsclient);
        runtime.dispatcher.startActor(tracer);
        SharedContext ctx = new SharedContext();
        tracer.log(ctx, "procUUID", "DEBUG", "blah", "testing...");
        self.pump();
        FakeWSActor sev = expectSocket(self.runtime, tracer._client._wsclient.url + "?token=" + tracer._client._wsclient.token);
        if (sev == null) {
            check(false, "No FakeWSActor returned.");
            return null;
        }
        sev.accept();
        self.pump();
        Open open = expectOpen(sev);
        if (open == null) { return null; }
        self.pump();
        return sev;
    }

    void doTestLog(String url) {
        Tracer tracer = newTracer(url);
        FakeWSActor sev = startTracer(tracer);
        if (sev == null) { return; }
        LogEvent evt = expectLogEvent(sev);
        if (evt == null) { return; }
        checkEqual("DEBUG", evt.level);
        checkEqual("blah", evt.category);
        checkEqual("testing...", evt.text);
    }

    // Unexpected messages are ignored.
    void testUnexpectedMessage() {
        Tracer tracer = newTracer("http://url/");
        FakeWSActor sev = startTracer(tracer);
        if (sev == null) { return; }
        sev.send("{\"type\": \"UnknownMessage\"}");
        self.pump();
        checkEqual("CONNECTED", sev.state);
    }

    void _subhandler(LogEvent evt, List<LogEvent> events) {
        events.add(evt);
    }

    void testSubscribe() {
        Tracer tracer = newTracer("http://url/");
        List<LogEvent> events = [];
        tracer.subscribe(bind(self, "_subhandler", [events]));
        self.pump();
        FakeWSActor sev = startTracer(tracer);
        if (sev == null) { return; }
        Open open = expectOpen(sev);
        if (open == null) { return; }
        Subscribe sub = expectSubscribe(sev);
        if (sub == null) { return; }
        LogEvent e = new LogEvent();
        e.text = "asdf";
        sev.send(e.encode());
        self.pump();
        checkEqual(1, events.size());
        LogEvent evt = events[0];
        checkEqual("asdf", evt.text );
    }

}

