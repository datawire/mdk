quark 1.0;

package mdk_test 1.0.0;

import quark.test;

void main(List<String> args) {
    test.run(args);
}

use mdk-1.0.q;

// We can switch to quark.mock whenever we switch to Quark > 1.0.133.
include mock.q;

import quark.test;

import tracing;
import tracing.protocol;
import mock;

class TracingTest extends ProtocolTest {

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
        return ?expectTracingEvent(evt, "mdk.protocol.Open");
    }

    LogEvent expectLogEvent(SocketEvent evt) {
        return ?expectTracingEvent(evt, "tracing.protocol.LogEvent");
    }

    /////////////////
    // Tests

    void testLog() {
        doTestLog(null);
    }

    void testLogCustomURL() {
        doTestLog("custom");
    }

    void doTestLog(String url) {
        tracing.Tracer tracer = new tracing.Tracer();
        if (url != null) {
            tracer.url = url;
        } else {
            url = tracer.url;
        }
        tracer.log("DEBUG", "blah", "testing...");
        self.pump();
        SocketEvent sev = self.expectSocket(url + "?token=" + tracer.token);
        if (sev == null) { return; }
        sev.accept();
        self.pump();
        Open open = expectOpen(sev);
        if (open == null) { return; }
        self.pump();
        LogEvent evt = expectLogEvent(sev);
        if (evt == null) { return; }
        LogMessage msg = ?evt.record;
        if (msg == null) {
            fail("expected a message");
            return;
        }
        checkEqual("DEBUG", msg.level);
        checkEqual("blah", msg.category);
        checkEqual("testing...", msg.text);
    }

}

import discovery;
import discovery.protocol;

class DiscoveryTest extends ProtocolTest {

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
        return ?expectDiscoveryEvent(evt, "mdk.protocol.Open");
    }

    Active expectActive(SocketEvent evt) {
        return ?expectDiscoveryEvent(evt, "discovery.protocol.Active");
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
        Discovery disco = new Discovery().connect();
        SocketEvent sev = startDisco(disco);
        if (sev == null) { return; }
    }

    void testFailedStart() {
        // ...
    }

    void testRegisterPreStart() {
        Discovery disco = new Discovery().connect();

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
        Discovery disco = new Discovery().connect();
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
        Discovery disco = new Discovery().connect();
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

    void testResolvePreStart() {
        Discovery disco = new Discovery().connect();

        Promise promise = disco._resolve("svc");
        checkEqual(false, promise.value().hasValue());

        SocketEvent sev = startDisco(disco);
        if (sev == null) { return; }

        Active active = new Active();
        active.node = new Node();
        active.node.service = "svc";
        active.node.address = "addr";
        active.node.version = "1.2.3";
        sev.send(active.encode());

        checkEqualNodes(active.node, ?promise.value().getValue());
    }

    void testResolvePostStart() {
        Discovery disco = new Discovery().connect();
        SocketEvent sev = startDisco(disco);

        Promise promise = disco._resolve("svc");
        checkEqual(false, promise.value().hasValue());

        Active active = new Active();
        active.node = new Node();
        active.node.service = "svc";
        active.node.address = "addr";
        active.node.version = "1.2.3";
        sev.send(active.encode());

        checkEqualNodes(active.node, ?promise.value().getValue());
    }

    void testResolveAfterNotification() {
        Discovery disco = new Discovery().connect();
        SocketEvent sev = startDisco(disco);

        Active active = new Active();
        active.node = new Node();
        active.node.service = "svc";
        active.node.address = "addr";
        active.node.version = "1.2.3";
        sev.send(active.encode());

        Promise promise = disco._resolve("svc");
        checkEqualNodes(active.node, ?promise.value().getValue());
    }

    // This variant caught a bug in the code, so it's useful to have all of
    // these even though they're seemingly similar.
    void testResolveBeforeAndBeforeNotification() {
        Discovery disco = new Discovery().connect();
        SocketEvent sev = startDisco(disco);
        Promise promise = disco._resolve("svc");
        Promise promise2 = disco._resolve("svc");
        checkEqual(false, promise.value().hasValue());
        checkEqual(false, promise2.value().hasValue());

        Active active = new Active();
        active.node = new Node();
        active.node.service = "svc";
        active.node.address = "addr";
        active.node.version = "1.2.3";
        sev.send(active.encode());

        checkEqualNodes(active.node, ?promise.value().getValue());
        checkEqualNodes(active.node, ?promise2.value().getValue());
    }

    void testResolveBeforeAndAfterNotification() {
        Discovery disco = new Discovery().connect();
        SocketEvent sev = startDisco(disco);
        Promise promise = disco._resolve("svc");

        Active active = new Active();
        active.node = new Node();
        active.node.service = "svc";
        active.node.address = "addr";
        active.node.version = "1.2.3";
        sev.send(active.encode());

        Promise promise2 = disco._resolve("svc");
        checkEqualNodes(active.node, ?promise.value().getValue());
        checkEqualNodes(active.node, ?promise2.value().getValue());
    }

    void testResolveDifferentActive() {
        Discovery disco = new Discovery().connect();
        SocketEvent sev = startDisco(disco);

        Active active = new Active();
        active.node = new Node();
        active.node.service = "svc";
        active.node.address = "addr";
        active.node.version = "1.2.3";
        sev.send(active.encode());

        Active active2 = new Active();
        active2.node = new Node();
        active2.node.service = "svc2";
        active2.node.address = "addr";
        active2.node.version = "1.2.3";
        sev.send(active2.encode());

        Promise promise = disco._resolve("svc");
        checkEqualNodes(active.node, ?promise.value().getValue());
    }

    void testLoadBalancing() {
        Discovery disco = new Discovery().connect();
        SocketEvent sev = startDisco(disco);

        Promise promise = disco._resolve("svc");
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
            Node node = ?disco._resolve("svc").value().getValue();
            checkEqual("addr" + (idx % count).toString(), node.address);
            idx = idx + 1;
        }
    }

    // Discovery.init() connects to the server, and sends the token:
    void testInit() {
        String token = "1234";
        Discovery disco = Discovery.init(token);
        self.pump();
        self.expectSocket(disco.url + "?token=" + token);
    }

    void testReconnect() {
        // ...
    }

    void testStop() {
        Discovery disco = new Discovery().connect();
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
        self.mock.pump();
        self.mock.pump();
        self.mock.pump();
        self.mock.pump();

        // At this point we should have nothing scheduled and socket should be
        // closed:
        checkEqual([sev], self.mock.events);
        checkEqual(true, sev.sock.closed);
        checkEqual(self.mock.executed, self.mock.tasks.size());
    }

}
