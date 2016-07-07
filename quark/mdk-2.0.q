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

@doc("Microservices Development Kit -- obtain a reference using MDK.init()")
namespace mdk {

    String _get(String name, String value) {
        return os.Environment.ENV.get(name, value);
    }

    @doc("Create an MDK instance.")
    MDK init() {
        return new MDKImpl();
    }

    @doc("Return a started MDK.")
    MDK start() {
        MDK m = new MDKImpl();
        m.start();
        return m;
    }

    @doc("""
         The MDK API consists of two interfaces: MDK and Session. The
         MDK interface holds globally scoped APIs and state associated
         with the microservice. The Session interface holds locally
         scoped APIs and state. A Session must be used sequentially.

         There will typically be one MDK instance for the entire
         process, and one instance of the Session object per
         thread/channel/request depending on how the MDK is integrated
         and used within the application framework of choice.
         """)
    interface MDK {

        static String CONTEXT_HEADER = "X-MDK-Context";

        @doc("""Start the uplink.""")
        void start();

        @doc("""Stop the uplink.""")
        void stop();

        @doc("Make our service known to discovery.")
        void register(String service, String version, String address);

        @doc("Create a new Session.")
        Session session();

        @doc("Create a new Session and join it to a distributed trace.")
        Session join(String encodedContext);

    }

    interface Session {

        @doc("Grabs the encoded context.")
        String inject();

        @doc("Record a log entry at the CRITICAL logging level.")
        void critical(String category, String text);

        @doc("Record a log entry at the ERROR logging level.")
        void error(String category, String text);

        @doc("Record a log entry at the WARN logging level.")
        void warn(String category, String text);

        @doc("Record a log entry at the INFO logging level.")
        void info(String category, String text);

        @doc("Record a log entry at the DEBUG logging level.")
        void debug(String category, String text);

        @doc("Look up a service name with a specific version via discovery.")
        Node resolve(String service, String version);

        @doc("Look up a service name with a specific version via discovery, with timeout.")
        Node resolve_until(String service, String version, float timeout);

        @doc("Asynchronously look up a service name/version via discovery. The result is returned as a promise.")
        Object resolve_async(String service, String version);

        @doc("Start an interaction.")
        void start_interaction();

        @doc("Record an interaction failure.")
        void fail(String message);

        @doc("Finish an interaction.")
        void finish_interaction();

        @doc("start_interaction(); callable(mdk); finish_interaction();")
        void interact(UnaryCallable callable);

    }

    class MDKImpl extends MDK {

        static Logger logger = new Logger("mdk");

        Discovery _disco = new Discovery();
        Tracer _tracer;
        String procUUID = mdk_protocol.uuid4();

        MDKImpl() {
            _disco.url = _get("MDK_DISCOVERY_URL", "wss://discovery-develop.datawire.io/");
            _disco.token = DatawireToken.getToken();

            String tracingURL = _get("MDK_TRACING_URL", "wss://tracing-develop.datawire.io/ws");
            String tracingQueryURL = _get("MDK_TRACING_API_URL", "wss://tracing-develop.datawire.io/api/logs");
            _tracer = Tracer.withURLsAndToken(tracingURL, tracingQueryURL, _disco.token);
            _tracer.initContext();
        }

        float _timeout() {
            return 10.0;
        }

        void start() {
            _disco.start();
        }

        void stop() {
            _disco.stop();
            _tracer.stop();
        }

        void register(String service, String version, String address) {
            Node node = new Node();
            node.service = service;
            node.version = version;
            node.address = address;
            node.properties = {};
            _disco.register(node);
        }

        SessionImpl session() {
            return new SessionImpl(self, null);
        }

        SessionImpl join(String encodedContext) {
            return new SessionImpl(self, encodedContext);
        }

    }

    class SessionImpl extends Session {

        MDKImpl _mdk;
        List<Node> _resolved = [];
        SharedContext _context;

        SessionImpl(MDKImpl mdk, String encodedContext) {
            _mdk = mdk;
            if (encodedContext == null || encodedContext == "") {
                _context = new SharedContext();
            } else {
                SharedContext ctx = SharedContext.decode(encodedContext);
                _context = ctx.start_span();
            }
        }

        void _log(String level, String category, String text) {
            _mdk._tracer.setContext(_context);
            _mdk._tracer.log(_mdk.procUUID, level, category, text);
        }

        void critical(String category, String text) {
            // XXX: no critical
            _mdk.logger.error(category + ": " + text);
            _log("CRITICAL", category, text);
        }

        void error(String category, String text) {
            _mdk.logger.error(category + ": " + text);
            _log("ERROR", category, text);
        }

        void warn(String category, String text) {
            _mdk.logger.warn(category + ": " + text);
            _log("WARN", category, text);
        }

        void info(String category, String text) {
            _mdk.logger.info(category + ": " + text);
            _log("INFO", category, text);
        }

        void debug(String category, String text) {
            _mdk.logger.debug(category + ": " + text);
            _log("DEBUG", category, text);
        }

        Promise _resolve(String service, String version) {
            return _mdk._disco._resolve(service, version).
                andThen(bind(self, "_resolvedCallback", []));
        }

        Object resolve_async(String service, String version) {
            return toNativePromise(_resolve(service, version));
        }

        Node resolve(String service, String version) {
            return resolve_until(service, version, _mdk._timeout());
        }

        Node resolve_until(String service, String version, float timeout) {
            return ?WaitForPromise.wait(self._resolve(service, version), timeout,
                                        "service " + service + "(" + version + ")");
        }

        Node _resolvedCallback(Node result) {
            _resolved.add(result);
            return result;
        }

        void start_interaction() {
            _resolved = [];
        }

        String inject() {
            return _context.encode();
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
                node.failure();
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
                node.success();
                idx = idx + 1;
            }
        }

        void interact(UnaryCallable cmd) {
            start_interaction();
            cmd.__call__(self);
            finish_interaction();
        }

    }

}
