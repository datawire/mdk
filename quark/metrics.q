/* Metric reporting sub-protocol. */

package datawire_mdk_tracing 2.0.22;

include protocol-1.0.q;

import mdk_protocol;

namespace mdk_metrics {
    class InteractionEvent extends Serializable, AckablePayload {
        static String _json_type = "interaction_event";

        @doc("Interaction start time, milliseconds since the Unix epoch.")
        long timestamp;

        long getTimestamp() {
            return self.timestamp;
        }

        @doc("Unique identifier for this interaction.")
        String uuid = Context.runtime().uuid();

        @doc("The UUID of the node that initiated the interaction.")
        String node;

        @doc("Map destination node UUID to success/failure of interaction.")
        Map<String,bool> results = {};
    }

    class InteractionAck extends Serializable {
        static String _json_type = "interaction_ack";

        @doc("Sequence number of the last interaction event message being acknowledged.")
        long sequence;
    }

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
            self._sendWithAcks.onConnected(self, self._dispatcher, websock);
        }

        void onPump() {
            self._sendWithAcks.onPump(self, self._dispatcher, self._sock);
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


