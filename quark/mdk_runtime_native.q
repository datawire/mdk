quark 1.0;

include native.js;

use py PyOpenSSL 16.1.0;
use py service_identity 16.0.0;
use py autobahn[twisted] 0.16.0;
use py crochet 1.5.0;
include native.py;

include mdk_runtime_common.q;

import mdk_runtime.actors;
import mdk_runtime.promise;


namespace mdk_runtime {

    @doc("""
    Native WSActor.

    State can be 'ERROR', 'CONNECTING', 'CONNECTED', 'DISCONNECTING',
    'DISCONNECTED'.
    """)
    class NativeWSActor extends WSActor, WSHandler {
        // XXX need better story for logging; perhaps integrate MDK Session with
        // the MessageDispatcher?
        Logger logger = new Logger("protocol");
        WebSocket socket;
        PromiseResolver factory;
        Actor originator;
        String url;
        String shortURL;
        MessageDispatcher dispatcher;
        String state = "CONNECTING";

        NativeWSActor(String url, Actor originator, PromiseResolver factory) {
            self.url = url;
            self.originator = originator;
            self.factory = factory;

            List<String> pieces = url.split("?");
            self.shortURL = pieces[0];
            if (pieces.size() > 1) {
                self.shortURL = self.shortURL + "?" + pieces[1].substring(0, 8);
            }
        }

        // Debugging
        void logTS(String message) {
            if (true) { return; }  // Ludicrous logging disabled. See also top of defaultRuntime().
            long now = Context.runtime().now();  // XXX FIXME
            int tenths = (now.truncateToInt() / 100) % 100000;  // in tenths of seconds
            if (tenths < 0) { tenths = tenths + 100000; }
            float seconds = tenths.toFloat() / 10.0;
            logger.debug(seconds.toString() + " " + message);
        }

        void logPrologue(String what) {
            String disMessage = "";
            if (self.dispatcher == null) {
                disMessage = ", no dispatcher";
            }
            logTS(what +
                  ", current state " + self.state +
                  ", originator " + self.originator.toString() +
                  ", I am " + self.toString() +
                  " [" + self.shortURL + "]" +
                  disMessage);
        }

        // Actor
        void onStart(MessageDispatcher dispatcher) {
            logPrologue("ws onStart");
            self.dispatcher = dispatcher;
            _connect(self.url, self);
        }

        void onMessage(Actor origin, Object message) {
            logPrologue("ws onMessage (actor message)");
            logTS("   message is from " + origin.toString());
            String messageId = message.getClass().id;
            if (messageId == "quark.String"
                && self.state == "CONNECTED") {
                logTS("   send-ish, message is: " + message.toString());
                log_to_file("sending: " + ?message);
                self.socket.send(?message);
                return;
            }
            if (messageId == "mdk_runtime.WSClose"
                && self.state == "CONNECTED") {
                logTS("   close-ish, switching to DISCONNECTING state");
                self.state = "DISCONNECTING";
                self.socket.close();
                return;
            }
            if (messageId == "mdk_runtime.WSClose"
                && self.state == "CONNECTING") {
                self.state = "DISCONNECTING";
                return;
            }
            logger.warn("ws onMessage got unhandled message: " +
                        message.getClass().id + " in state " + self.state);
        }

        // WSHandler
        void onWSConnected(WebSocket socket) {
            logPrologue("onWSConnected");
            if (self.state != "CONNECTING") {
                logTS("Connection event when transitioned out of CONNECTING." +
                      "Current state: " + self.state);
                socket.close();
                return;
            }
            self.state = "CONNECTED";
            self.socket = socket;
            self.factory.resolve(self);
        }

        void onWSError(WebSocket socket, WSError error) {
            logPrologue("onWSError");
            logTS("onWSError, reason is: " + error.toString());
            if (self.state == "CONNECTING") {
                logger.error("Error connecting to WebSocket: " + error.toString());
                self.state = "ERROR";
                self.factory.reject(new WSConnectError(error.toString()));
                return;
            }
            logger.error("WebSocket error: " + error.toString());
        }

        void onWSMessage(WebSocket socket, String message) {
            logPrologue("onWSMessage");
            logTS("onWSMessage, message is: " + message);
            log_to_file("received: " + message);
            self.dispatcher.tell(self, new WSMessage(message), self.originator);
        }

        void onWSFinal(WebSocket socket) {
            logPrologue("onWSFinal");
            if (self.state == "DISCONNECTING" || self.state == "CONNECTED") {
                self.state = "DISCONNECTED";
                self.socket = null;
                self.dispatcher.tell(self, new WSClosed(), self.originator);
            }
        }
    }

    macro void _connect(String url, WSHandler handler)
        $java{}
        $py{native.connect(($url), ($handler))}
        $js{native.connect(($url), ($handler))}
        $rb{false}
    ;

    @doc("Client WebSocket support")
    class NativeWebSockets extends WebSockets {
        // XXX need better story for logging; perhaps integrate MDK Session with
        // the MessageDispatcher?
        Logger logger = new Logger("protocol");

        MessageDispatcher dispatcher;
        List<WSActor> connections = [];

        mdk_runtime.promise.Promise connect(String url, Actor originator) {
            logger.debug(originator.toString() + "requested connection to "
                         + url);
            PromiseResolver factory = new PromiseResolver(self.dispatcher);
            NativeWSActor actor = new NativeWSActor(url, originator, factory);
            connections.add(actor);
            self.dispatcher.startActor(actor);
            return factory.promise;
        }

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object message) {}

        void onStop() {
            int idx = 0;
            while (idx < connections.size()) {
                self.dispatcher.tell(self, new WSClose(), self.connections[idx]);
                idx = idx + 1;
            }
        }
    }

    class _ScheduleCallable extends UnaryCallable {
        NativeTime timeService;
        Actor requester;
        String event;

        _ScheduleCallable(NativeTime timeService, Actor requester, String event) {
            self.timeService = timeService;
            self.requester = requester;
            self.event = event;
        }

        Object call(Object arg) {
            timeService.dispatcher.tell(
                self.timeService, new Happening(self.event, self.timeService.time()), self.requester);
            return null;
        }
    }

    macro void _schedule(UnaryCallable callable, float delayInSeconds)
        $java{}
        $py{native.schedule(($callable), ($delayInSeconds))}
        $js{native.schedule(($callable), ($delayInSeconds))}
        $rb{false}
    ;

    macro float _now()
        $java{(1.0)}
        $py{native.now()}
        $js{native.now()}
        $rb{(1.0)}
    ;

    @doc("Time and scheduling via native code.")
    class NativeTime extends Time, SchedulingActor {
        MessageDispatcher dispatcher;
        bool stopped = false;

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onStop() {
            self.stopped = true;
        }

        void onMessage(Actor origin, Object msg) {
            if (self.stopped) {
                return;
            }
            Schedule sched = ?msg;
            float seconds = sched.seconds;
            _schedule(new _ScheduleCallable(self, origin, sched.event), seconds);
        }

        float time() {
            return _now();
        }
    }

    class _NativeLaterCallerCallable extends UnaryCallable {
        Task toCall;

        _NativeLaterCallerCallable(Task t) {
            self.toCall = t;
        }

        Object call(Object arg) {
            self.toCall.onExecute(null);
            return null;
        }
    }

    class _NativeLaterCaller extends _CallLater {
        void schedule(Task t) {
            _schedule(new _NativeLaterCallerCallable(t), 0.0);
        }

        void runAll() { }
    }

    macro String _env_get(String name)
        $java{($name)}
        $py{native.env_get($name)}
        $js{native.env_get($name)}
        $rb{($name)}
    ;

    @doc("Environment variables via native code.")
    class NativeEnvVars extends EnvironmentVariables {
        EnvironmentVariable var(String name) {
            return new EnvironmentVariable(name, _env_get(name));
        }
    }

    macro bool isJava() $py{False} $js{false} $java{true} $rb{false};
    macro bool isRuby() $py{False} $js{false} $java{false} $rb{true};

    @doc("Create a MDKRuntime with the default configuration and start its actors.")
    MDKRuntime defaultRuntime() {
        //logging.makeConfig().setLevel("DEBUG").configure();
        MDKRuntime runtime = new MDKRuntime();

        EnvironmentVariables envVars;
        Time timeService;
        SchedulingActor schedActor;
        WebSockets websockets;
        if (isJava() || isRuby()) {
            runtime.dispatcher = new MessageDispatcher(new _QuarkRuntimeLaterCaller());
            envVars = new RealEnvVars();
            timeService = new QuarkRuntimeTime();
            schedActor = ?timeService;
            websockets = new QuarkRuntimeWebSockets();
        } else {
            runtime.dispatcher = new MessageDispatcher(new _NativeLaterCaller());
            envVars = new NativeEnvVars();
            timeService = new NativeTime();
            schedActor = ?timeService;
            websockets = new NativeWebSockets();
        }
        runtime.dependencies.registerService("envvar", envVars);
        runtime.dependencies.registerService("time", timeService);
        runtime.dependencies.registerService("schedule", schedActor);
        runtime.dependencies.registerService("websockets", websockets);

        mdk_runtime.files.FileActor fileActor = new mdk_runtime.files.FileActorImpl(runtime);
        runtime.dependencies.registerService("files", fileActor);

        runtime.dispatcher.startActor(schedActor);
        runtime.dispatcher.startActor(websockets);
        runtime.dispatcher.startActor(fileActor);

        return runtime;
    }

}
