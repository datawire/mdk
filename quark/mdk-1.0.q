quark 1.0;

package datawire_mdk 1.0.0;

// DATAWIRE MDK

use discovery-2.0.q;
use tracing-1.0.q;
use datawire_introspection.q;

import discovery;
import tracing;
import quark.concurrent;
import datawire_introspection;

// Sketch of a more wholistic API. This is WIP.

namespace msdk {

    String _get(String var, String value) {
        return os.Environment.ENV.get(var, value);
    }

    MDK init() {
        return new MDKImpl();
    }

    interface MDK {

        void start();

        void stop();

        void register(String service, String version, String address);

        Promise resolve(String service, String version);

        void begin();

        SharedContext context();

        void fail(String message);

        void end();

        void protect(UnaryCallable callable);

        void log(String level, String category, String text);

        void critical(String category, String text);

        void error(String category, String text);

        void warn(String category, String text);

        void info(String category, String text);

        void debug(String category, String text);

    }

    class MDKImpl extends MDK {

        static Logger logger = new Logger("mdk");

        Lock _mutex = new Lock();
        Discovery _disco = new Discovery();
        Tracer _tracer = new Tracer();
        Node _me = null;

        List<Node> _resolved = [];

        MDKImpl() {
            _disco.url = _get("MDK_DISCOVERY_URL", "wss://discovery-beta.datawire.io");
            _disco.token = DatawireToken.getToken();
            _tracer.url = _get("MDK_TRACING_URL", "wss://philadelphia-test.datawire.io/ws");
        }

        void start() {
            _disco.start();
        }

        void register(String service, String version, String address) {
            _mutex.acquire();
            if (_me != null) {
                _mutex.release();
                panic("already registered");
            }

            _me = new Node(service, version, address, {});
            _disco.register(_me);
            _mutex.release();
        }

        void stop() {
            _disco.stop();
            _tracer.stop();
        }

        void log(String level, String category, String text) {
            _tracer.log(level, category, text);
        }

        void critical(String category, String text) {
            // XXX: no critical
            logger.error(category + ": " + text);
            log("CRITICAL", category, text);
        }

        void error(String category, String text) {
            logger.error(category + ": " + text);
            log("ERROR", category, text);
        }

        void warn(String category, String text) {
            logger.warn(category + ": " + text);
            log("WARN", category, text);
        }

        void info(String category, String text) {
            logger.info(category + ": " + text);
            log("INFO", category, text);
        }

        void debug(String category, String text) {
            logger.debug(category + ": " + text);
            log("DEBUG", category, text);
        }

        Node _resolvedCallback(Node result) {
            _resolved.add(result);
            return result;
        }

        Promise resolve(String service, String version) {
            return _disco.resolve(service).
                andThen(bind(self, "_resolvedCallback", []));
        }

        void begin() {
            // XXX: pushes a level on the stack
        }

        SharedContext context() {
            return _tracer.getContext();
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

        void end() {
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
        }

        void protect(UnaryCallable cmd) {
            begin();
            cmd.__call__(self);
            end();
        }

    }

}
