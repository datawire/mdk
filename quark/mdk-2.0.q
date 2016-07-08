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

    @doc("Create an unstarted instance of the MDK.")
    MDK init() {
        return new MDKImpl();
    }

    @doc("""
         Create a started instance of the MDK. This is equivalent to
         callint init() followed by start() on the resulting instance.
         """)
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

         The MDK instance is responsible for communicating with
         foundational services like discovery and tracing.

         There will typically be one MDK instance for the entire
         process, and one instance of the Session object per
         thread/channel/request depending on how the MDK is integrated
         and used within the application framework of choice.
         """)
    interface MDK {

        @doc("This header is used to propogate shared context for distributed traces.")
        static String CONTEXT_HEADER = "X-MDK-Context";

        @doc("""
             Start the MDK. An MDK instance will not communicate with
             foundational services unless it is started.
             """)
        void start();

        @doc("""
             Stop the MDK. When the MDK stops unregisters any service
             endpoints from the discovery system. This should always
             be done prior to process exit in order to propogate node
             shutdowns in realtime rather than waiting for heartbeats
             to detect node departures.
             """)
        void stop();

        @doc("""
             Registers a service endpoint with the discovery
             system. This can be called at any point, however
             registered endpoints will not be advertised to the
             discovery system until the MDK is started.
             """)
        void register(String service, String version, String address);

        @doc("""
             Creates a new Session. A Session created in this way will
             result in a new distributed trace. This should therefore
             be used primarily by edge services. Intermediary and
             foundational services should make use of
             join(encodedContext) in order to preserve distributed
             traces.
             """)
        Session session();

        @doc("""
             Create a new Session and join it to a distributed trace.
             """)
        Session join(String encodedContext);

    }

    @doc("""
         A session provides a lightweight sequential context that a
         microservice can use in the context of any application
         framework in order to manage its interactions with other
         microservices. It provides simple APIs for service
         resolution, distributed tracing, and circuit breakers.

         A microservices architecture enables small self contained
         units of business logic to be implemented by separate teams
         working on isolated services based on the languages and
         frameworks best suited for their problem domain.

         Any given microservice will contain sequential business logic
         implemented in a variety of ways depending on the application
         framework chosen. For example it may be a long running
         thread, a simple blocking request handler, or a chained
         series of reactive handlers in an async environment.

         For the most part this business logic can be implemented
         exactly as prescribed by the application framework of choice,
         however in a microservices architecture, some special care
         needs to be taken when this business logic interacts with
         other microservices.

         Because microservices are updated with much higher frequency
         than normal web applications, the interactions between them
         form key points that require extra care beyond normal web
         interactions in order to avoid creating a system that is both
         extremely fragile, unreliable, and opaque.

         Realtime service resolution, distributed tracing, and
         resilience heuristics such as circuit breakers provide the
         foundational behavior required at these interaction
         points. These capabilites must be combined with the defensive
         coding practice of intelligent fallback behavior when remote
         services are unavailable or misbehaving, in order to build a
         robust microservice application.

         Because of this, a session is expected to be created and made
         available to all business logic within a given microservice,
         e.g. on a per request basis, as a thread local, part of a
         context object, etc depending on the application framework of
         choice.
         """)
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

        @doc("""
             Locate a compatible service instance.
             """)
        Node resolve(String service, String version);

        @doc("""
             Locate a compatible service instance with a non-default timeout.
             """)
        Node resolve_until(String service, String version, float timeout);

        @doc("""
             Locate a compatible service instance asynchronously. The result is returned as a promise.
             """)
        Object resolve_async(String service, String version);

        @doc("""
             Start an interaction with a remote service.

             The session tracks any nodes resolved during an
             interactin with a remote service.

             The service resolution API permits a compatible instance
             of the service to be located. In addition, it tracks
             which exact instances are in use during any
             interaction. Should the interaction fail, circuit breaker
             state is updated for those nodes, and all involved
             instances involved are reported to the tracing services.

             This permits realtime reporting of integration issues
             when services are updated, and also allows circuit
             breakers to mitigate the impact of any such issues.
             """)
        void start_interaction();

        @doc("""
             Record an interaction as failed.

             This will update circuit breaker state for the remote
             nodes, as well as reporting all nodes involved to the
             tracing system.
             """)
        void fail_interaction(String message);

        @doc("""
             Finish an interaction.

             This marks an interaction as completed.
             """)
        void finish_interaction();

        @doc("""
             This is a convenience API that will perform
             start_interaction() followed by callable(ssn) followed by
             finish_interaction().

             """)
        void interact(UnaryCallable callable);

    }

    class MDKImpl extends MDK {

        static Logger logger = new Logger("mdk");

        Discovery _disco = new Discovery();
        Tracer _tracer;
        String procUUID = Context.runtime().uuid();

        MDKImpl() {
            _disco.url = _get("MDK_DISCOVERY_URL", "wss://discovery.datawire.io/");
            _disco.token = DatawireToken.getToken();

            String tracingURL = _get("MDK_TRACING_URL", "wss://tracing.datawire.io/ws");

            _tracer = Tracer.withURLsAndToken(tracingURL, "", _disco.token);
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

        void fail_interaction(String message) {
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
            self.error("interaction failure", text);
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
