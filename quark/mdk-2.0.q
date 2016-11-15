quark 1.0;

package datawire_mdk 2.0.33;

// DATAWIRE MDK

include mdk_runtime.q;
include util-1.0.q;
include introspection-1.0.q;
include discovery-3.0.q;
include tracing-2.0.q;
include rtp.q;
include metrics.q;

import mdk_discovery;
import mdk_tracing;
import mdk_introspection;
import mdk_util;
import mdk_runtime;
import quark.concurrent;
import mdk_rtp;
import mdk_metrics;
// Needs to be last import, until we rip out Quark's built-in Promise:
import mdk_runtime.promise;


@doc("Microservices Development Kit -- obtain a reference using MDK.init()")
namespace mdk {

    String _get(EnvironmentVariables env, String name, String value) {
        return env.var(name).orElseGet(value);
    }

    @doc("Convert 'name' or 'fallback:name' into an Environment.")
    OperationalEnvironment _parseEnvironment(String environment) {
        String name = environment;
        String fallback = null;
        if (environment.find(":") != -1) {
            fallback = environment.split(":")[0];
            name = environment.split(":")[1];
        }
        OperationalEnvironment result = new OperationalEnvironment();
        result.name = name;
        result.fallbackName = fallback;
        return result;
    }

    @doc("Create an unstarted instance of the MDK.")
    MDK init() {
        // XXX once we have native package wrappers for this code they will
        // create the DI registry and actor disptacher. Until then, we create those
        // here:
        return new MDKImpl(mdk_runtime.defaultRuntime());
    }

    @doc("""
         Create a started instance of the MDK. This is equivalent to
         calling init() followed by start() on the resulting instance.
         """)
    MDK start() {
        MDK m = init();
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

         A note on versions: service versions indicate API compatibility, not
         releases of the underlying code. They should be in the form
         MAJOR.MINOR, e.g. '2.11'. Major versions indicates
         incompatibility: '1.0' is incompatible with '2.11'. Minor versions
         indicate backwards compatibility with new features: a client that wants
         version '1.1' can talk to version '1.1' and '1.2' but not to version
         '1.0'.
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
             Set the default timeout for MDK sessions.

             This is the maximum timeout; if a joined session has a lower
             timeout that will be used.
             """)
        void setDefaultDeadline(float seconds);

        @doc("DEPRECATED, use setDefaultDeadline().")
        void setDefaultTimeout(float seconds);

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
             Create a new Session and join it to an existing distributed sesion.

             This should only ever be done once per an encoded context. That
             means you should only use it for RPC or similar one-off calls. If
             you received the encoded context via a broadcast medium (pub/sub,
             message queues with multiple readers, etc.) you should use
             childSession() instead.
             """)
        Session join(String encodedContext);

        @doc("""
             Create a new Session. The given encoded distributed session's
             properties will be used to configure the new Session,
             e.g. overrides will be preserved. However, because this is a new
             Session the timeout will not be copied from the encoded session.

             This is intended for use for encoded context received via a
             broadcast medium (pub/sub, message queues with multiple readers,
             etc.). If you know only you received the encoded context,
             e.g. you're coding a server that receives the context from a HTTP
             request, you should join() instead.
             """)
        Session derive(String encodedContext);

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

        @doc("Returns an externalized representation of the distributed session.")
        String externalize();

        @doc("Record a log entry at the CRITICAL logging level.")
        LoggedMessageId critical(String category, String text);

        @doc("Record a log entry at the ERROR logging level.")
        LoggedMessageId error(String category, String text);

        @doc("Record a log entry at the WARN logging level.")
        LoggedMessageId warn(String category, String text);

        @doc("Record a log entry at the INFO logging level.")
        LoggedMessageId info(String category, String text);

        @doc("Record a log entry at the DEBUG logging level.")
        LoggedMessageId debug(String category, String text);

        @doc("EXPERIMENTAL: Set the logging level for the session.")
        void trace(String level);


        @doc("""
             EXPERIMENTAL; requires MDK_EXPERIMENTAL=1 environment variable to
             function.

             Override service resolution for the current distributed
             session. All attempts to resolve *service*, *version*
             will be replaced with an attempt to resolve *target*,
             *targetVersion*. This effect will be propogated to any
             downstream services involved in the distributed session.
             """)
        void route(String service, String version, String target, String targetVersion);

        @doc("""
             Locate a compatible service instance.

             Uses a minimum of 10 seconds and the timeout set on the session.
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

        @doc("""
             Set how many seconds the session is expected to live from this point.

             If a timeout has previously been set the new timeout will only be
             used if it is lower than the existing timeout.

             The MDK will not enforce the timeout. Rather, it provides the
             information to any process or server in the same session (even if
             they are on different machines). By passing this timeout to
             blocking APIs you can ensure timeouts are enforced across a whole
             distributed session.
             """)
        void setDeadline(float seconds);

        @doc("DEPRECATED, use setDeadline().")
        void setTimeout(float seconds);

        @doc("""
             Return how many seconds until the session ought to end.

             This will only be accurate across multiple servers insofar as their
             clocks are in sync.

             If a timeout has not been set the result will be null.
             """)
        float getRemainingTime();

        @doc("Return the value of a property from the distributed session.")
        Object getProperty(String property);

        @doc("""
        Set a property on the distributed session.

        The key should be prefixed with a namespace so that it doesn't conflict
        with built-in properties, e.g. 'examplenamespace:myproperty' instead of
        'myproperty'.

        The value should be JSON serializable.
        """)
        void setProperty(String property, Object value);

        @doc("Return whether the distributed session has a property.")
        bool hasProperty(String property);

        @doc("Return the session's Environment.")
        OperationalEnvironment getEnvironment();
    }

    class MDKImpl extends MDK {

        Logger logger = new Logger("mdk");
        Map<String,Object> _reflection_hack = null;

        MDKRuntime _runtime;
        WSClient _wsclient;
        OpenCloseSubscriber _openclose;
        Discovery _disco;
        DiscoverySource _discoSource;
        Tracer _tracer = null;
        MetricsClient _metrics = null;
        // In the future this should be based on the Docker container id, AWS
        // instance id, etc. when possible:
        String procUUID = Context.runtime().uuid();
        bool _running = false;
        float _defaultTimeout = null;
        // The OperationalEnvironment this MDK is configured for, e.g. "sandbox" or
        // "production".
        OperationalEnvironment _environment;

        @doc("Choose DiscoverySource based on environment variables.")
        DiscoverySourceFactory getDiscoveryFactory(EnvironmentVariables env) {
            String config = env.var("MDK_DISCOVERY_SOURCE").orElseGet("");
            if (config == "") {
                config = "datawire:" + DatawireToken.getToken(env);
            }
            DiscoverySourceFactory result = null;
            if (config.startsWith("datawire:")) {
                result = new DiscoClientFactory(_wsclient);
            } else {
                if (config.startsWith("synapse:path=")) {
                    result = mdk_discovery.synapse
                        .Synapse(config.substring(13, config.size()),
                                 self._environment);
                } else {
                    if (config.startsWith("static:nodes=")) {
                        String json = config.substring(13, config.size());
                        result = mdk_discovery.StaticRoutes.parseJSON(json);
                    } else {
                        panic("Unknown MDK discovery source: " + config);
                    }
                }
            }
            return result;
        }

        @doc("Choose FailurePolicy based on environment variables.")
        FailurePolicyFactory getFailurePolicy(MDKRuntime runtime) {
            String config = runtime.getEnvVarsService()
                .var("MDK_FAILURE_POLICY").orElseGet("");
            if (config == "recording") {
                return new mdk_discovery.RecordingFailurePolicyFactory();
            } else {
                return new CircuitBreakerFactory(runtime);
            }
        }

        @doc("Get a WSClient, unless env variables suggest the user doesn't want one.")
        WSClient getWSClient(MDKRuntime runtime) {
            EnvironmentVariables env = runtime.getEnvVarsService();
            // If we have token we can start WSClient, otherwise we can't:
            String token = env.var("DATAWIRE_TOKEN").orElseGet("");
            String disco_config = env.var("MDK_DISCOVERY_SOURCE").orElseGet("");
            if (token == "") {
                // Another place we can get the token:
                if (disco_config.startsWith("datawire:")) {
                    token = disco_config.substring(9, disco_config.size());
                } else {
                    return null;
                }
            }

            EnvironmentVariable ddu = env.var("MDK_SERVER_URL");
            String url = ddu.orElseGet("wss://mcp.datawire.io/rtp");
            return new WSClient(runtime, getRTPParser(), url, token);
        }

        MDKImpl(MDKRuntime runtime) {
            _reflection_hack = new Map<String,Object>();
            _runtime = runtime;
            _environment = _parseEnvironment(runtime.getEnvVarsService()
                                             .var("MDK_ENVIRONMENT")
                                             .orElseGet("sandbox"));
            if (!runtime.dependencies.hasService("failurepolicy_factory")) {
                runtime.dependencies.registerService("failurepolicy_factory",
                                                     getFailurePolicy(runtime));
            }
            if (runtime.dependencies.hasService("tracer")) {
                _tracer = ?_runtime.dependencies.getService("tracer");
            }
            _disco = new Discovery(runtime);
            _wsclient = getWSClient(runtime);
            // Make sure we register OpenCloseSubscriber first so that Open
            // message gets sent first.
            if (_wsclient != null) {
                _openclose = new OpenCloseSubscriber(_wsclient, procUUID, _environment);
            }
            EnvironmentVariables env = runtime.getEnvVarsService();
            DiscoverySourceFactory discoFactory = getDiscoveryFactory(env);
            _discoSource = discoFactory.create(_disco, runtime);
            if (discoFactory.isRegistrar()) {
                runtime.dependencies.registerService("discovery_registrar", _discoSource);
            }
            if (_wsclient != null) {
                if (_tracer == null) {
                    _tracer = Tracer(runtime, _wsclient);
                }
                _metrics = new MetricsClient(_wsclient);
            }
        }

        float _timeout() {
            return 10.0;
        }

        void start() {
            self._running = true;
            // XXX maybe decouple starting WSClient from actually connecting,
            // since that's race-condition-y, e.g. if it connects fast enough it
            // could deliver messages to disco source actor that hasn't started
            // yet.
            if (_wsclient != null) {
                _runtime.dispatcher.startActor(_wsclient);
                _runtime.dispatcher.startActor(_openclose);
                _runtime.dispatcher.startActor(_tracer);
                _runtime.dispatcher.startActor(_metrics);
            }
            _runtime.dispatcher.startActor(_disco);
            _runtime.dispatcher.startActor(_discoSource);
        }

        void stop() {
            self._running = false;
            // Make sure we shut down discovery source/registrar first, as it
            // may wish to send some unregistration messages:
            _runtime.dispatcher.stopActor(_discoSource);
            _runtime.dispatcher.stopActor(_disco);
            if (_wsclient != null) {
                _runtime.dispatcher.stopActor(_tracer);
                _runtime.dispatcher.stopActor(_openclose);
                _runtime.dispatcher.stopActor(_wsclient);
            }
            _runtime.stop();
        }

        void register(String service, String version, String address) {
            Node node = new Node();
            node.id = procUUID;
            node.service = service;
            node.version = version;
            node.address = address;
            node.environment = self._environment;
            node.properties = { "datawire_nodeId": procUUID };
            _disco.register(node);
        }

        void setDefaultDeadline(float seconds) {
            self._defaultTimeout = seconds;
        }

        void setDefaultTimeout(float seconds) {
            setDefaultDeadline(seconds);
        }

        Session session() {
            SessionImpl session = new SessionImpl(self, null, self._environment);
            if (_defaultTimeout != null) {
                session.setDeadline(_defaultTimeout);
            }
            return session;
        }

        Session derive(String encodedContext) {
            SessionImpl session = ?self.session();
            SharedContext parent = SharedContext.decode(encodedContext);
            session._context.properties = parent.properties;
            if (session._context.properties.contains("timeout")) {
                session._context.properties.remove("timeout");
            }
            session.info("mdk",
                         "This session is derived from trace " + parent.traceId + " " +
                         parent.clock.clocks.toString());
            return session;
        }

        Session join(String encodedContext) {
            SessionImpl session = new SessionImpl(self, encodedContext,
                                                  self._environment);
            if (_defaultTimeout != null) {
                session.setDeadline(_defaultTimeout);
            }
            return session;
        }

    }

    macro Object sanitize(Object obj) $js{_qrt.sanitize_undefined($obj)}$py{$obj}$rb{$obj}$java{$obj};

    class _TLSInit extends TLSInitializer<bool> {
        bool getValue() { return false; }
    }

    @doc("""
    Information about the message that was just logged.
    """)
    class LoggedMessageId {
        @doc("The ID of the trace this message was logged in.")
        String traceId;

        @doc("The causal clock level within the trace.")
        List<int> causalLevel;

        @doc("The operational environment.")
        String environment;

        @doc("The fallback operational environment.")
        String environmentFallback;

        LoggedMessageId(String traceId, List<int> causalLevel,
                        String environment, String environmentFallback) {
            self.traceId = traceId;
            self.causalLevel = causalLevel;
            self.environment = environment;
            self.environmentFallback = environmentFallback;
        }
    }

    class SessionImpl extends Session {

        static Map<String,int> _levels = {"CRITICAL": 0,
                                          "ERROR": 1,
                                          "WARN": 2,
                                          "INFO": 3,
                                          "DEBUG": 4};
        // True if we're inside logging code path:
        static TLS<bool> _inLogging = new TLS<bool>(new _TLSInit());

        MDKImpl _mdk;
        // Each List<Node> is another stack level added by start_interaction.
        List<List<Node>> _resolved = [];
        // Each InteractionEvent is another stack level added by start interaction.
        List<InteractionEvent> _interactionReports = [];
        SharedContext _context;
        bool _experimental = false;

        SessionImpl(MDKImpl mdk, String encodedContext, OperationalEnvironment localEnvironment) {
            _experimental = (mdk._runtime.getEnvVarsService()
                             .var("MDK_EXPERIMENTAL").orElseGet("") != "");
            _mdk = mdk;
            encodedContext = ?sanitize(encodedContext);
            if (encodedContext == null || encodedContext == "") {
                _context = new SharedContext();
                _context.environment = localEnvironment;
            } else {
                SharedContext ctx = SharedContext.decode(encodedContext);
                _context = ctx.start_span();
            }
            // Start a dummy interaction so that we don't blow up if someone
            // does something that requires an interaction to be
            // started. Well-written code shouldn't rely on this.
            self.start_interaction();
        }

        OperationalEnvironment getEnvironment() {
            return self._context.environment;
        }

        Object getProperty(String property) {
            return _context.properties[property];
        }

        void setProperty(String property, Object value) {
            _context.properties[property] = value;
        }

        bool hasProperty(String property) {
            return _context.properties.contains(property);
        }

        void setTimeout(float timeout) {
            setDeadline(timeout);
        }

        void setDeadline(float timeout) {
            float current = getRemainingTime();
            if (current == null) {
                current = timeout;
            }
            if (timeout > current) {
                timeout = current;
            }
            setProperty("timeout",  _mdk._runtime.getTimeService().time() + timeout);
        }

        float getRemainingTime() {
            float deadline = ?getProperty("timeout");
            if (deadline == null) {
                return null;
            }
            return deadline - _mdk._runtime.getTimeService().time();
        }

        void route(String service, String version, String target, String targetVersion) {
            Map<String,List<Map<String,String>>> routes;
            if (!hasProperty("routes")) {
                routes = {};
                setProperty("routes", routes);
            } else {
                routes = ?getProperty("routes");
            }

            List<Map<String,String>> targets;
            if (routes.contains(service)) {
                targets = routes[service];
            } else {
                targets = [];
                routes[service] = targets;
            }

            targets.add({"version": version, "target": target, "targetVersion": targetVersion});
        }

        void trace(String level) {
            setProperty("trace", level);
        }

        static int _level(String level) {
            if (_levels.contains(level)) {
                return _levels[level];
            } else {
                return 0;
            }
        }

        bool _enabled(String level) {
            int ilevel = _level("INFO");
            if (hasProperty("trace")) {
                ilevel = _level(?getProperty("trace"));
            }

            return _level(level) <= ilevel;
        }

        LoggedMessageId _log(String level, String category, String text) {
            if (_inLogging.getValue()) {
                // We're being called recursively. We don't want logging
                // inside the tracer to trigger logging to the tracer! So
                // sadly we have to just drop the message on the floor.
                return null;
            }
            _inLogging.setValue(true);
            LogEvent evt = createLogEvent(_context, _mdk.procUUID, level,
                                          category, text);
            if (_mdk._tracer != null && _enabled(level)) {
                _mdk._tracer.log(evt);
            }
            _inLogging.setValue(false);
            return new LoggedMessageId(_context.traceId,
                                       evt.context.clock.clocks,
                                       _context.environment.name,
                                       _context.environment.fallbackName);
        }

        LoggedMessageId critical(String category, String text) {
            return _log("CRITICAL", category, text);
        }

        LoggedMessageId error(String category, String text) {
            return _log("ERROR", category, text);
        }

        LoggedMessageId warn(String category, String text) {
            return _log("WARN", category, text);
        }

        LoggedMessageId info(String category, String text) {
            return _log("INFO", category, text);
        }

        LoggedMessageId debug(String category, String text) {
            return _log("DEBUG", category, text);
        }

        Promise _resolve(String service, String version) {
            if (_experimental) {
                Map<String,List<Map<String,String>>> routes = ?getProperty("routes");
                if (routes != null && routes.contains(service)) {
                    List<Map<String,String>> targets = routes[service];
                    int idx = 0;
                    while (idx < targets.size()) {
                        Map<String,String> target = targets[idx];
                        if (versionMatch(target["version"], version)) {
                            service = target["target"];
                            version = target["targetVersion"];
                            break;
                        }
                        idx = idx + 1;
                    }
                }
            }

            return _mdk._disco.resolve(service, version, self.getEnvironment()).
                andThen(bind(self, "_resolvedCallback", []));
        }

        Object resolve_async(String service, String version) {
            return toNativePromise(_resolve(service, version));
        }

        Node resolve(String service, String version) {
            float timeout = _mdk._timeout();
            float session_timeout = self.getRemainingTime();
            if (session_timeout != null && session_timeout < timeout) {
                timeout = session_timeout;
            }
            return resolve_until(service, version, timeout);
        }

        Node resolve_until(String service, String version, float timeout) {
            return ?WaitForPromise.wait(self._resolve(service, version), timeout,
                                        "service " + service + "(" + version + ")");
        }

        Node _resolvedCallback(Node result) {
            _current_interaction().add(result);
            return result;
        }

        List<Node> _current_interaction() {
            return _resolved[_resolved.size() - 1];
        }

        void start_interaction() {
            InteractionEvent interactionReport = new InteractionEvent();
            interactionReport.node = _mdk.procUUID;
            interactionReport.timestamp =
                (1000.0 * _mdk._runtime.getTimeService().time()).round();
            interactionReport.session = _context.traceId;
            interactionReport.environment = _context.environment;
            _interactionReports.add(interactionReport);
            _resolved.add([]);
        }

        String inject() {
            return externalize();
        }

        String externalize() {
            String result = _context.encode();
            _context.tick();
            return result;
        }

        void fail_interaction(String message) {
            // All Nodes resolved in current interaction are marked as having
            // failed:
            List<Node> suspects = _current_interaction();
            _resolved[_resolved.size() - 1] = [];

            List<String> involved = [];
            int idx = 0;
            while (idx < suspects.size()) {
                Node node = suspects[idx];
                idx = idx + 1;
                involved.add(node.toString());
                node.failure();
                _interactionReports[_interactionReports.size() - 1].addNode(node, false);
            }

            String text = "no dependent services involved";

            if (involved.size() > 0) {
                text = "involved: " + ", ".join(involved);
            }

            self.error("interaction failure", text + "\n\n" + message);
        }

        void finish_interaction() {
            // Pops a level off the stack
            List<Node> nodes = _current_interaction();
            _resolved.remove(_resolved.size() - 1);
            InteractionEvent report = _interactionReports
                .remove(_interactionReports.size() - 1);
            int idx = 0;
            while (idx < nodes.size()) {
                Node node = nodes[idx];
                node.success();
                report.addNode(node, true);
                idx = idx + 1;
            }
            if (_mdk._metrics != null) {
                _mdk._metrics.sendInteraction(report);
            }
        }

        void interact(UnaryCallable cmd) {
            start_interaction();
            // XXX use callSafely to add error-handling and fail_interaction
            // support
            cmd.__call__(self);
            finish_interaction();
        }

    }

}
