quark 1.0;

package datawire_mdk 2.0.0;

// DATAWIRE MDK

use discovery-3.0.q;
use tracing-2.0.q;
use introspection-1.0.q;
use util-1.0.q;

import mdk_discovery;
import mdk_tracing;
import mdk_introspection;
import mdk_util;

import quark.concurrent;

namespace mdk {

    String _get(String name, String value) {
        return os.Environment.ENV.get(name, value);
    }

    MDK init() {
        return new MDKImpl();
    }

    interface MDK {

        @doc("""Start the uplink.""")
        void start();

        @doc("""Stop the uplink.""")
        void stop();

        void register(String service, String version, String address);

        Promise _resolve(String service, String version);

        Object resolve(String service, String version);

        Node resolve_until(String service, String version, float timeout);

        void init_context();

        @doc("Retrieve our existing context.")
        SharedContext context();

        @doc("Join an existing context.")
        void join_context(SharedContext context);
        void join_encoded_context(String encodedContext);

        @doc("Start an interaction.")
        void start_interaction();

        void fail(String message);

        @doc("Finish an interaction.")
        void finish_interaction();

        void interact(UnaryCallable callable);

        void critical(String category, String text);

        void error(String category, String text);

        void warn(String category, String text);

        void info(String category, String text);

        void debug(String category, String text);

    }

    class MDKImpl extends MDK {

        static Logger logger = new Logger("mdk");

        Discovery _disco = new Discovery();
        Tracer _tracer;

        List<Node> _resolved = [];
        String procUUID = mdk_protocol.uuid4();

        MDKImpl() {
            _disco.url = _get("MDK_DISCOVERY_URL", "wss://discovery-develop.datawire.io");
            _disco.token = DatawireToken.getToken();

            String tracingURL = _get("MDK_TRACING_URL", "wss://tracing-develop.datawire.io/ws");

            _tracer = Tracer.withURLsAndToken(tracingURL, "", _disco.token);
            _tracer.initContext();
        }

        float _timeout() {
            return 10.0;
        }

        void start() {
            _disco.start();
        }

        void register(String service, String version, String address) {
            Node node = new Node();
            node.service = service;
            node.version = version;
            node.address = address;
            node.properties = {};
            _disco.register(node);
        }

        void stop() {
            _disco.stop();
            _tracer.stop();
        }

        void _log(String level, String category, String text) {
            _tracer.log(self.procUUID, level, category, text);
        }

        void critical(String category, String text) {
            // XXX: no critical
            logger.error(category + ": " + text);
            _log("CRITICAL", category, text);
        }

        void error(String category, String text) {
            logger.error(category + ": " + text);
            _log("ERROR", category, text);
        }

        void warn(String category, String text) {
            logger.warn(category + ": " + text);
            _log("WARN", category, text);
        }

        void info(String category, String text) {
            logger.info(category + ": " + text);
            _log("INFO", category, text);
        }

        void debug(String category, String text) {
            logger.debug(category + ": " + text);
            _log("DEBUG", category, text);
        }

        Node _resolvedCallback(Node result) {
            _resolved.add(result);
            return result;
        }

        Promise _resolve(String service, String version) {
            return _disco._resolve(service).
                andThen(bind(self, "_resolvedCallback", []));
        }

        Object resolve_async(String service, String version) {
            return toNativePromise(_resolve(service, version));
        }

        Node resolve(String service, String version) {
            return resolve_until(service, version, _timeout());
        }

        Node resolve_until(String service, String version, float timeout) {
            return ?WaitForPromise.wait(self._resolve(service, version), timeout,
                                        "service " + service + "(" + version + ")");
        }

        void start_interaction() {
            // _tracer.start_span();
        }

        SharedContext context() {
            return _tracer.getContext();
        }

        void init_context() {
            _tracer.initContext();
        }

        @doc("Join an existing context.")
        void join_context(SharedContext context) {
            _tracer.joinContext(context);
        }

        void join_encoded_context(String encodedContext) {
            _tracer.joinEncodedContext(encodedContext);
        }

        void fail(String message) {
            List<Node> suspects = _resolved;
            _resolved = [];

            List<String> involved = [];
            int idx = 0;
            while (idx < suspects.size()) {
                Node node = suspects[idx];
                idx = idx + 1;
                involved.add(node.toString());
                // XXX: want to call node.failure() here in order to
                // activate circuit breaker logic
            }

            String text = "involved: " + ", ".join(involved) + "\n\n" + message;
            self.error("integration", text);
        }

        void finish_interaction() {
            // XXX: pops a level off the stack
            List<Node> nodes = _resolved;
            _resolved = [];

            int idx = 0;
            while (idx < nodes.size()) {
                Node node = nodes[idx];
                // XXX: want to call node.success() here in order to
                // activate circuit breaker logic
                idx = idx + 1;
            }

            // _tracer.finish_span();
        }

        void interact(UnaryCallable cmd) {
            start_interaction();
            cmd.__call__(self);
            finish_interaction();
        }

    }

}
