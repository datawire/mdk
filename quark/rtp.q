quark 1.0;

include protocol-1.0.q;

import mdk_protocol;
import quark.reflect;

namespace mdk_rtp {

    @doc("Create a JSONParser that can read all messages to/from the MCP.")
    JSONParser getRTPParser() {
        JSONParser parser = new JSONParser();
        // Open/close protocol
        parser.register("open", Class.get("mdk_protocol.Open"));
        parser.register("mdk.protocol.Open", Class.get("mdk_protocol.Open"));
        parser.register("close", Class.get("mdk_protocol.Close"));
        parser.register("mdk.protocol.Close", Class.get("mdk_protocol.Close"));
        parser.register("discovery.protocol.Close", Class.get("mdk_protocol.Close"));
        // Discovery protocol
        parser.register("active", Class.get("mdk_discovery.protocol.Active"));
        parser.register("discovery.protocol.Expire", Class.get("mdk_discovery.protocol.Expire"));
        parser.register("expire", Class.get("mdk_discovery.protocol.Expire"));
        parser.register("discovery.protocol.Expire", Class.get("mdk_discovery.protocol.Expire"));
        parser.register("clear", Class.get("mdk_discovery.protocol.Clear"));
        parser.register("discovery.protocol.Clear", Class.get("mdk_discovery.protocol.Clear"));
        // Tracing protocol
        parser.register("log", Class.get("mdk_tracing.protocol.LogEvent"));
        parser.register("logack", Class.get("mdk_tracing.protocol.LogAck"));
        parser.register("mdk_tracing.protocol.LogAckEvent", Class.get("mdk_tracing.protocol.LogAck"));
        parser.register("subscribe", Class.get("mdk_tracing.protocol.Subscribe"));
        return parser;
    }
}
