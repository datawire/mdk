quark 1.0;

/* Metric reporting sub-protocol. */

package datawire_mdk_tracing 2.0.33;

include protocol-1.0.q;
include discovery-3.0.q;

import mdk_discovery;
import mdk_protocol;

namespace mdk_metrics {
    @doc("Wire protocol message for reporting interaction results to MCP.")
    class InteractionEvent extends Serializable, AckablePayload {
        static String _json_type = "interaction_event";

        @doc("Interaction start time, milliseconds since the Unix epoch.")
        long start_timestamp;

        @doc("Interaction end time, milliseconds since the Unix epoch.")
        long end_timestamp;

        @doc("Interaction (really, session's) environment.")
        OperationalEnvironment environment;

        long getTimestamp() {
            return self.start_timestamp;
        }

        @doc("Unique identifier for this interaction.")
        String uuid = Context.runtime().uuid();

        @doc("Identifier for current session.")
        String session;

        @doc("The UUID of the node that initiated the interaction.")
        String node;

        @doc("Map destination node UUID to success=1/failure=0 of interaction.")
        Map<String,int> results = {};

        @doc("Add the result of communicating with a specific node.")
        void addNode(Node destination, bool success) {
            int value = 0;
            if (success) {
                value = 1;
            }
            self.results[destination.getId()] = value;
        }
    }

    @doc("Wire protocol message for MCP to acknowledge InteractionEvent receipt.")
    class InteractionAck extends Serializable {
        static String _json_type = "interaction_ack";

        @doc("Sequence number of the last interaction event message being acknowledged.")
        long sequence;
    }

    @doc("Mini-protocol for sending metrics to MCP.")
    class MetricsClient extends WSClientSubscriber {
        MessageDispatcher _dispatcher;
        Actor _sock = null; // The websocket we're connected to, if any
        SendWithAcks _sendWithAcks = new SendWithAcks();

        MetricsClient(WSClient wsclient) {
            wsclient.subscribe(self);
        }

        @doc("Queue info about interaction to be sent to the MCP.")
        void sendInteraction(InteractionEvent evt) {
            self._sendWithAcks.send(evt._json_type, evt);
        }

        void onStart(MessageDispatcher dispatcher) {
            self._dispatcher = dispatcher;
        }

        void onStop() {}

        void onMessage(Actor origin, Object message) {
            _subscriberDispatch(self, message);
        }

        void onWSConnected(Actor websock) {
            self._sock = websock;
            self._sendWithAcks.onConnected(new WSSend(self, self._dispatcher, self._sock));
        }

        void onPump() {
            self._sendWithAcks.onPump(new WSSend(self, self._dispatcher, self._sock));
        }

        void onMessageFromServer(Object message) {
            String type = message.getClass().id;
            if (type == "metrics.InteractionAck") {
                InteractionAck ack = ?message;
                self._sendWithAcks.onAck(ack.sequence);
                return;
            }
        }
    }
}
