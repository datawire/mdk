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

    MDK init() {
        return new MDKImpl();
    }

    interface MDK {

        void start();

        void stop();

        void register(String service, String version);

        Node resolve(String service, String version);

        void begin();

        void fail();

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

        Lock _mutex = new Lock();
        Discovery _disco = new Discovery();
        Tracer _tracer = new Tracer();
        Node _me = null;

        List<Node> _resolved = [];

        MDKImpl() {
            //_disco.url = "wss://discovery-beta.datawire.io";
            _disco.url = "ws://discovery-temp.datawire.io";
            _disco.token = DatawireToken.getToken();
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

            _me = new Node();
            _me.service = service;
            _me.version = version;
            _me.address = address;
            _me.properties = {};
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
            log("CRITICAL", category, text);
        }

        void error(String category, String text) {
            log("ERROR", category, text);
        }

        void warn(String category, String text) {
            log("WARN", category, text);
        }

        void info(String category, String text) {
            log("INFO", category, text);
        }

        void debug(String category, String text) {
            log("DEBUG", category, text);
        }

        Node resolve(String service, String version) {
            Node node = _disco.resolve(service);
            _resolved.add(node);
            return node;
        }

        void begin() {
            // XXX: pushes a level on the stack
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
