quark 1.0;

package datawire_mdk_test 1.0.0;

use ../mdk-2.0.q;

import quark.test;
import quark.reflect;

void main(List<String> args) {
    test.run(args);
}

import mdk_tracing;
import mdk_tracing.protocol;
import mdk_runtime;

MDKRuntime fakeRuntime() {
    MDKRuntime result = new MDKRuntime();
    FakeTime timeService = new FakeTime();
    result.dependencies.registerService("time", timeService);
    result.dependencies.registerService("schedule", timeService);
    result.dependencies.registerService("websockets",
                                        new FakeWebSockets(result.dispatcher));
    result.dispatcher.startActor(timeService);
    return result;
}

FakeWSActor expectSocket(MDKRuntime runtime, String url) {
    FakeWebSockets ws = ?runtime.getWebSocketsService();
    FakeWSActor actor = ws.lastConnection();
    if (actor.url != url) {
        return null;
    } else {
        return actor;
    }
}

class TracingTest {
    MDKRuntime runtime;

    TracingTest() {
        self.runtime = fakeRuntime();
    }

    void pump() {
        FakeTime timeService = ?runtime.getTimeService();
        timeService.pump();
    }

    /////////////////
    // Helpers

    ProtocolEvent expectTracingEvent(FakeWSActor sev, String expectedType) {
        String msg = sev.expectTextMessage();
        if (msg == null) { return null; }
        ProtocolEvent evt = TracingEvent.decode(msg);
        String type = evt.getClass().getName();
        if (check(type == expectedType, "expected " + expectedType + " event, got " + type)) {
            return ?evt;
        } else {
            return null;
        }
    }

    Open expectOpen(FakeWSActor evt) {
        return ?expectTracingEvent(evt, "mdk_protocol.Open");
    }

    LogEvent expectLogEvent(FakeWSActor evt) {
        return ?expectTracingEvent(evt, "mdk_tracing.protocol.LogEvent");
    }

    Subscribe expectSubscribe(FakeWSActor evt) {
        return ?expectTracingEvent(evt, "mdk_tracing.protocol.Subscribe");
    }

    /////////////////
    // Tests

    void testLog() {
        doTestLog(null);
    }

    void testLogCustomURL() {
        doTestLog("custom");
    }

    FakeWSActor startTracer(Tracer tracer) {
        tracer.initContext();
        tracer.log("procUUID", "DEBUG", "blah", "testing...");
        self.pump();
        FakeWSActor sev = expectSocket(self.runtime, tracer.url + "?token=" + tracer.token);
        if (sev == null) { return null; }
        sev.accept();
        self.pump();
        Open open = expectOpen(sev);
        if (open == null) { return null; }
        self.pump();
        return sev;
    }

    void doTestLog(String url) {
        Tracer tracer = new Tracer(runtime);
        if (url != null) {
            tracer.url = url;
        } else {
            url = tracer.url;
        }
        FakeWSActor sev = startTracer(tracer);
        LogEvent evt = expectLogEvent(sev);
        if (evt == null) { return; }
        checkEqual("DEBUG", evt.level);
        checkEqual("blah", evt.category);
        checkEqual("testing...", evt.text);
    }

    // Unexpected messages are ignored.
    void testUnexpectedMessage() {
        Tracer tracer = new Tracer(runtime);
        FakeWSActor sev = startTracer(tracer);
        sev.send("{\"type\": \"UnknownMessage\"}");
        self.pump();
        checkEqual("CONNECTED", sev.state);
    }

    void _subhandler(LogEvent evt, List<LogEvent> events) {
        events.add(evt);
    }

    void testSubscribe() {
        Tracer tracer = new Tracer(runtime);
        List<LogEvent> events = [];
        tracer.subscribe(bind(self, "_subhandler", [events]));
        self.pump();
        FakeWSActor sev = expectSocket(self.runtime, tracer.url + "?token=" + tracer.token);
        if (sev == null) { return; }
        sev.accept();
        self.pump();
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

import mdk_discovery;
import mdk_discovery.protocol;


class UnSerializable extends Serializable {
    static UnSerializable construct() {
        return null;
    }
}

class SerializableTest {
    // Unexpected messages result in a null, not in a panic
    void testUnexpected() {
        Object result = Serializable.decodeClass(Class.get("datawire_mdk_test.UnSerializable"),
                                                 "{\"type\": \"UnSerializable\"}");
        checkEqual(null, result);
    }
}

class DiscoveryTest {
    MDKRuntime runtime;

    DiscoveryTest() {
        self.runtime = fakeRuntime();
    }

    void pump() {
        FakeTime timeService = ?runtime.getTimeService();
        timeService.pump();
    }

    /////////////////
    // Helpers

    ProtocolEvent expectDiscoveryEvent(FakeWSActor sev, String expectedType) {
        String msg = sev.expectTextMessage();
        if (msg == null) { return null; }
        ProtocolEvent evt = DiscoveryEvent.decode(msg);
        String type = evt.getClass().getName();
        if (check(type == expectedType, "expected " + expectedType + " event, got " + type)) {
            return ?evt;
        } else {
            return null;
        }
    }

    Open expectOpen(FakeWSActor evt) {
        return ?expectDiscoveryEvent(evt, "mdk_protocol.Open");
    }

    Active expectActive(FakeWSActor evt) {
        return ?expectDiscoveryEvent(evt, "mdk_discovery.protocol.Active");
    }

    void checkEqualNodes(Node expected, Node actual) {
        checkEqual(expected.service, actual.service);
        checkEqual(expected.address, actual.address);
        checkEqual(expected.version, actual.version);
        checkEqual(expected.properties, actual.properties);
    }

    FakeWSActor startDisco(Discovery disco) {
        disco.start();
        self.pump();
        FakeWSActor sev = expectSocket(self.runtime, disco.url);
        if (sev == null) { return null; }
        sev.accept();
        sev.send(new Open().encode());
        return sev;
    }

    /////////////////
    // Tests

    void testStart() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);
        if (sev == null) { return; }
    }

    void testFailedStart() {
        // ...
    }

    void testRegisterPreStart() {
        Discovery disco = new Discovery(runtime).connect();

        Node node = new Node();
        node.service = "svc";
        node.address = "addr";
        node.version = "1.2.3";
        disco.register(node);

        FakeWSActor sev = startDisco(disco);
        if (sev == null) { return; }

        Open open = expectOpen(sev);
        if (open == null) { return; }

        Active active = expectActive(sev);
        if (active == null) { return; }
        checkEqualNodes(node, active.node);
    }

    void testRegisterPostStart() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Node node = new Node();
        node.service = "svc";
        node.address = "addr";
        node.version = "1.2.3";
        disco.register(node);

        Open open = expectOpen(sev);
        if (open == null) { return; }
        Active active = expectActive(sev);
        if (active == null) { return; }
        checkEqualNodes(node, active.node);
    }

    void testRegisterTheNiceWay() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Node node = new Node();
        node.service = "svc";
        node.address = "addr";
        node.version = "1.2.3";
        disco.register_service(node.service, node.address, node.version);

        Open open = expectOpen(sev);
        if (open == null) { return; }
        Active active = expectActive(sev);
        if (active == null) { return; }
        checkEqualNodes(node, active.node);
    }

    Node doActive(FakeWSActor sev, String svc, String addr, String version) {
        Active active = new Active();
        active.node = new Node();
        active.node.service = svc;
        active.node.address = addr;
        active.node.version = version;
        sev.send(active.encode());
        return active.node;
    }

    void testResolvePreStart() {
        Discovery disco = new Discovery(runtime).connect();

        Promise promise = disco._resolve("svc", "1.0");
        checkEqual(false, promise.value().hasValue());

        FakeWSActor sev = startDisco(disco);
        if (sev == null) { return; }

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        checkEqualNodes(node, ?promise.value().getValue());
    }

    void testResolvePostStart() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Promise promise = disco._resolve("svc", "1.0");
        checkEqual(false, promise.value().hasValue());

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        checkEqualNodes(node, ?promise.value().getValue());
    }

    void testResolveAfterNotification() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        Promise promise = disco._resolve("svc", "1.0");
        checkEqualNodes(node, ?promise.value().getValue());
    }

    // This variant caught a bug in the code, so it's useful to have all of
    // these even though they're seemingly similar.
    void testResolveBeforeAndBeforeNotification() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);
        Promise promise = disco._resolve("svc", "1.0");
        Promise promise2 = disco._resolve("svc", "1.0");
        checkEqual(false, promise.value().hasValue());
        checkEqual(false, promise2.value().hasValue());

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        checkEqualNodes(node, ?promise.value().getValue());
        checkEqualNodes(node, ?promise2.value().getValue());
    }

    void testResolveBeforeAndAfterNotification() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);
        Promise promise = disco._resolve("svc", "1.0");

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        Promise promise2 = disco._resolve("svc", "1.0");
        checkEqualNodes(node, ?promise.value().getValue());
        checkEqualNodes(node, ?promise2.value().getValue());
    }

    void testResolveDifferentActive() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Node node = doActive(sev, "svc", "addr", "1.2.3");
        doActive(sev, "svc2", "addr", "1.2.3");

        Promise promise = disco._resolve("svc", "1.0");
        checkEqualNodes(node, ?promise.value().getValue());
    }

    void testResolveVersionAfterActive() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Node n1 = doActive(sev, "svc", "addr1.0", "1.0.0");
        Node n2 = doActive(sev, "svc", "addr1.2.3", "1.2.3");

        Promise promise = disco._resolve("svc", "1.0");
        checkEqualNodes(n1, ?promise.value().getValue());
        promise = disco._resolve("svc", "1.1");
        checkEqualNodes(n2, ?promise.value().getValue());
    }

    void testResolveVersionBeforeActive() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Promise p1 = disco._resolve("svc", "1.0");
        Promise p2 = disco._resolve("svc", "1.1");

        Node n1 = doActive(sev, "svc", "addr1.0", "1.0.0");
        Node n2 = doActive(sev, "svc", "addr1.2.3", "1.2.3");

        checkEqualNodes(n1, ?p1.value().getValue());
        checkEqualNodes(n2, ?p2.value().getValue());
    }

    void testResolveBreaker() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Node n1 = doActive(sev, "svc", "addr1", "1.0.0");
        Node n2 = doActive(sev, "svc", "addr2", "1.0.0");

        Promise p = disco._resolve("svc", "1.0");
        checkEqualNodes(n1, ?p.value().getValue());
        p = disco._resolve("svc", "1.0");
        checkEqualNodes(n2, ?p.value().getValue());

        Node failed = ?p.value().getValue();
        int idx = 0;
        while (idx < disco.threshold) {
            failed.failure();
            idx = idx + 1;
        }

        p = disco._resolve("svc", "1.0");
        checkEqualNodes(n1, ?p.value().getValue());
        p = disco._resolve("svc", "1.0");
        checkEqualNodes(n1, ?p.value().getValue());
    }

    void testLoadBalancing() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Promise promise = disco._resolve("svc", "1.0");
        checkEqual(false, promise.value().hasValue());

        Active active = new Active();

        int idx = 0;
        int count = 10;
        while (idx < count) {
            active.node = new Node();
            active.node.service = "svc";
            active.node.address = "addr" + idx.toString();
            active.node.version = "1.2.3";
            sev.send(active.encode());
            idx = idx + 1;
        }

        idx = 0;
        while (idx < count*10) {
            Node node = ?disco._resolve("svc", "1.0").value().getValue();
            checkEqual("addr" + (idx % count).toString(), node.address);
            idx = idx + 1;
        }
    }

    void testReconnect() {
        // ...
    }

    // Unexpected messages are ignored.
    void testUnexpectedMessage() {
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);
        sev.send("{\"type\": \"UnknownMessage\"}");
        self.pump();
        checkEqual("CONNECTED", sev.state);
    }

    void testStop() {
        FakeTime timeService = ?runtime.getTimeService();
        Discovery disco = new Discovery(runtime).connect();
        FakeWSActor sev = startDisco(disco);

        Node node = new Node();
        node.service = "svc";
        node.address = "addr";
        node.version = "1.2.3";
        disco.register(node);

        Open open = expectOpen(sev);
        if (open == null) { return; }
        Active active = expectActive(sev);
        if (active == null) { return; }

        disco.stop();
        // Might take some cleanup to stop everything:
        timeService.advance(15.0);
        self.pump();
        self.pump();
        self.pump();
        self.pump();

        // At this point we should have nothing scheduled and socket should be
        // closed:
        FakeWebSockets ws = ?runtime.getWebSocketsService();
        checkEqual([sev], ws.fakeActors); // Only the one connection
        checkEqual("DISCONNECTED", sev.state);
        checkEqual(0, timeService.scheduled());
    }

}


class MDKHighLevelAPITest {
    // It's possible to call the MDK init().
    void testInit() {
        mdk.init();
    }
}

class UtilTest {

    void testVersionMatch() {
        checkEqual(true, versionMatch("1", "1.0.0"));
        checkEqual(true, versionMatch("1.0", "1.0.0"));
        checkEqual(true, versionMatch("1.0.0", "1.0.0"));
        checkEqual(true, versionMatch("1.0.0", "1.0"));
        checkEqual(true, versionMatch("1.0.0", "1"));

        checkEqual(true, versionMatch("1.0", "1.1"));
        checkEqual(true, versionMatch("1.0", "1.1.0"));
        checkEqual(true, versionMatch("1.1", "1.1"));
        checkEqual(true, versionMatch("1.1", "1.1.0"));

        checkEqual(false, versionMatch("1.2", "1.1.0"));
        checkEqual(false, versionMatch("2.0", "1.1.0"));
        checkEqual(false, versionMatch("1.3", "1.2"));
    }

}

class CircuitBreakerTest {

    void testBreakerTrips() {
        Node node = new Node();
        node._policy = new CircuitBreaker(node, 3, 1.0);
        checkEqual(true, node.available());
        node.failure();
        checkEqual(true, node.available());
        node.failure();
        checkEqual(true, node.available());
        node.failure();
        checkEqual(false, node.available());
    }

}
