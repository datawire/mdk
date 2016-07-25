quark 1.0;

package datawire_mdk_test 1.0.0;

use mdk-2.0.q;

import quark.test;
import quark.mock;
import quark.reflect;

void main(List<String> args) {
    test.run(args);
}

import mdk_tracing;
import mdk_tracing.protocol;
import mdk_runtime;
import dependency;

Dependencies dependencies() {
    Dependencies dependencies = new Dependencies();
    MessageDispatcher dispatcher = new MessageDispatcher();
    FakeTime timeService = new FakeTime();
    dependencies.registerService("time", timeService);
    dependencies.registerActor("schedule", dispatcher._startActor(timeService));
    return dependencies;
}

class TracingTest extends MockRuntimeTest {
    Dependencies deps;

    TracingTest() {
        super();
        deps = dependencies();
    }

    void pump() {
        self.mock.pump();
        FakeTime timeService = ?deps.getService("time");
        timeService.pump();
    }

    /////////////////
    // Helpers

    ProtocolEvent expectTracingEvent(SocketEvent sev, String expectedType) {
        TextMessage msg = sev.expectTextMessage();
        if (msg == null) { return null; }
        ProtocolEvent evt = TracingEvent.decode(msg.text);
        String type = evt.getClass().getName();
        if (check(type == expectedType, "expected " + expectedType + " event, got " + type)) {
            return ?evt;
        } else {
            return null;
        }
    }

    Open expectOpen(SocketEvent evt) {
        return ?expectTracingEvent(evt, "mdk_protocol.Open");
    }

    LogEvent expectLogEvent(SocketEvent evt) {
        return ?expectTracingEvent(evt, "mdk_tracing.protocol.LogEvent");
    }

    /////////////////
    // Tests

    void testLog() {
        doTestLog(null);
    }

    void testLogCustomURL() {
        doTestLog("custom");
    }

    SocketEvent startTracer(Tracer tracer) {
        tracer.initContext();
        tracer.log("procUUID", "DEBUG", "blah", "testing...");
        self.pump();
        SocketEvent sev = self.expectSocket(tracer.url + "?token=" + tracer.token);
        if (sev == null) { return null; }
        sev.accept();
        self.pump();
        Open open = expectOpen(sev);
        if (open == null) { return null; }
        self.pump();
        return sev;
    }

    void doTestLog(String url) {
        Tracer tracer = new Tracer(dependencies());
        if (url != null) {
            tracer.url = url;
        } else {
            url = tracer.url;
        }
        SocketEvent sev = startTracer(tracer);
        LogEvent evt = expectLogEvent(sev);
        if (evt == null) { return; }
        checkEqual("DEBUG", evt.level);
        checkEqual("blah", evt.category);
        checkEqual("testing...", evt.text);
    }

    // Unexpected messages are ignored.
    void testUnexpectedMessage() {
        Tracer tracer = new Tracer(dependencies());
        SocketEvent sev = startTracer(tracer);
        sev.send("{\"type\": \"UnknownMessage\"}");
        self.pump();
        checkEqual(false, sev.sock.closed);
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

class DiscoveryTest extends MockRuntimeTest {

    Dependencies deps;

    DiscoveryTest() {
        super();
        deps = dependencies();
    }

    void pump() {
        self.mock.pump();
        FakeTime timeService = ?deps.getService("time");
        timeService.pump();
    }

    /////////////////
    // Helpers

    ProtocolEvent expectDiscoveryEvent(SocketEvent sev, String expectedType) {
        TextMessage msg = sev.expectTextMessage();
        if (msg == null) { return null; }
        ProtocolEvent evt = DiscoveryEvent.decode(msg.text);
        String type = evt.getClass().getName();
        if (check(type == expectedType, "expected " + expectedType + " event, got " + type)) {
            return ?evt;
        } else {
            return null;
        }
    }

    Open expectOpen(SocketEvent evt) {
        return ?expectDiscoveryEvent(evt, "mdk_protocol.Open");
    }

    Active expectActive(SocketEvent evt) {
        return ?expectDiscoveryEvent(evt, "mdk_discovery.protocol.Active");
    }

    void checkEqualNodes(Node expected, Node actual) {
        checkEqual(expected.service, actual.service);
        checkEqual(expected.address, actual.address);
        checkEqual(expected.version, actual.version);
        checkEqual(expected.properties, actual.properties);
    }

    SocketEvent startDisco(Discovery disco) {
        disco.start();
        self.pump();
        SocketEvent sev = self.expectSocket(disco.url);
        if (sev == null) { return null; }
        sev.accept();
        sev.send(new Open().encode());
        return sev;
    }

    /////////////////
    // Tests

    void testStart() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);
        if (sev == null) { return; }
    }

    void testFailedStart() {
        // ...
    }

    void testRegisterPreStart() {
        Discovery disco = new Discovery(dependencies()).connect();

        Node node = new Node();
        node.service = "svc";
        node.address = "addr";
        node.version = "1.2.3";
        disco.register(node);

        SocketEvent sev = startDisco(disco);
        if (sev == null) { return; }

        Open open = expectOpen(sev);
        if (open == null) { return; }

        Active active = expectActive(sev);
        if (active == null) { return; }
        checkEqualNodes(node, active.node);
    }

    void testRegisterPostStart() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

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
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

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

    Node doActive(SocketEvent sev, String svc, String addr, String version) {
        Active active = new Active();
        active.node = new Node();
        active.node.service = svc;
        active.node.address = addr;
        active.node.version = version;
        sev.send(active.encode());
        return active.node;
    }

    void testResolvePreStart() {
        Discovery disco = new Discovery(dependencies()).connect();

        Promise promise = disco._resolve("svc", "1.0");
        checkEqual(false, promise.value().hasValue());

        SocketEvent sev = startDisco(disco);
        if (sev == null) { return; }

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        checkEqualNodes(node, ?promise.value().getValue());
    }

    void testResolvePostStart() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

        Promise promise = disco._resolve("svc", "1.0");
        checkEqual(false, promise.value().hasValue());

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        checkEqualNodes(node, ?promise.value().getValue());
    }

    void testResolveAfterNotification() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        Promise promise = disco._resolve("svc", "1.0");
        checkEqualNodes(node, ?promise.value().getValue());
    }

    // This variant caught a bug in the code, so it's useful to have all of
    // these even though they're seemingly similar.
    void testResolveBeforeAndBeforeNotification() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);
        Promise promise = disco._resolve("svc", "1.0");
        Promise promise2 = disco._resolve("svc", "1.0");
        checkEqual(false, promise.value().hasValue());
        checkEqual(false, promise2.value().hasValue());

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        checkEqualNodes(node, ?promise.value().getValue());
        checkEqualNodes(node, ?promise2.value().getValue());
    }

    void testResolveBeforeAndAfterNotification() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);
        Promise promise = disco._resolve("svc", "1.0");

        Node node = doActive(sev, "svc", "addr", "1.2.3");

        Promise promise2 = disco._resolve("svc", "1.0");
        checkEqualNodes(node, ?promise.value().getValue());
        checkEqualNodes(node, ?promise2.value().getValue());
    }

    void testResolveDifferentActive() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

        Node node = doActive(sev, "svc", "addr", "1.2.3");
        doActive(sev, "svc2", "addr", "1.2.3");

        Promise promise = disco._resolve("svc", "1.0");
        checkEqualNodes(node, ?promise.value().getValue());
    }

    void testResolveVersionAfterActive() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

        Node n1 = doActive(sev, "svc", "addr1.0", "1.0.0");
        Node n2 = doActive(sev, "svc", "addr1.2.3", "1.2.3");

        Promise promise = disco._resolve("svc", "1.0");
        checkEqualNodes(n1, ?promise.value().getValue());
        promise = disco._resolve("svc", "1.1");
        checkEqualNodes(n2, ?promise.value().getValue());
    }

    void testResolveVersionBeforeActive() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

        Promise p1 = disco._resolve("svc", "1.0");
        Promise p2 = disco._resolve("svc", "1.1");

        Node n1 = doActive(sev, "svc", "addr1.0", "1.0.0");
        Node n2 = doActive(sev, "svc", "addr1.2.3", "1.2.3");

        checkEqualNodes(n1, ?p1.value().getValue());
        checkEqualNodes(n2, ?p2.value().getValue());
    }

    void testResolveBreaker() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

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
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);

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

    // Discovery.init() connects to the server, and sends the token:
    void testInit() {
        String token = "1234";
        Discovery disco = Discovery.init(token, dependencies());
        self.pump();
        self.expectSocket(disco.url + "?token=" + token);
    }

    void testReconnect() {
        // ...
    }

    // Unexpected messages are ignored.
    void testUnexpectedMessage() {
        Discovery disco = new Discovery(dependencies()).connect();
        SocketEvent sev = startDisco(disco);
        sev.send("{\"type\": \"UnknownMessage\"}");
        self.pump();
        checkEqual(false, sev.sock.closed);
    }

    void testStop() {
        Dependencies deps = dependencies();
        FakeTime timeService = ?deps.getService("time");
        Discovery disco = new Discovery(deps).connect();
        SocketEvent sev = startDisco(disco);

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
        checkEqual([sev], self.mock.events);
        checkEqual(true, sev.sock.closed);
        checkEqual(self.mock.executed, self.mock.tasks.size());
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
