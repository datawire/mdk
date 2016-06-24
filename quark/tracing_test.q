quark 1.0;

package tracing_test 1.0.0;

use tracing-1.0.q;
// We can switch to quark.mock whenever we switch to Quark > 1.0.133.
include mock.q;

import quark.test;

import tracing;
import tracing.protocol;
import mock;

void main(List<String> args) {
    test.run(args);
}

class TracingTest extends ProtocolTest {

    /////////////////
    // Helpers

    // XXX: dup
    ProtocolEvent expectProtocolEvent(SocketEvent sev, String expectedType) {
        TextMessage msg = sev.expectTextMessage();
        if (msg == null) { return null; }
        ProtocolEvent evt = ProtocolEvent.decode(msg.text);
        String type = evt.getClass().getName();
        if (check(type == expectedType, "expected " + expectedType + " event, got " + type)) {
            return ?evt;
        } else {
            return null;
        }
    }

    Open expectOpen(SocketEvent evt) {
        return ?expectProtocolEvent(evt, "mdk.protocol.Open");
    }

    LogEvent expectLogEvent(SocketEvent evt) {
        return ?expectProtocolEvent(evt, "tracing.protocol.LogEvent");
    }

    /////////////////
    // Tests

    void testLog() {
        tracing.Logger logger = new tracing.Logger();
        self.pump();
        SocketEvent sev = self.expectSocket(logger.url + "/?token=" + logger.token);
        if (sev == null) { return; }
        sev.accept();
        self.pump();
        Open open = expectOpen(sev);
        if (open == null) { return; }
        logger.log("DEBUG", "blah", "testing...");
        self.pump();
        LogEvent evt = expectLogEvent(sev);
        if (evt == null) { return; }
        LogMessage msg = ?evt.record;
        checkEqual("DEBUG", msg.level);
        checkEqual("blah", msg.category);
        checkEqual("testing...", msg.text);
    }

}
