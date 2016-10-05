quark 1.0;

package datawire_mdk_runtime 2.0.14;

include mdk_runtime_common.q;

import quark.os;
import mdk_runtime.actors;
import mdk_runtime.promise;


namespace mdk_runtime {

    @doc("""
    WSActor that uses current Quark runtime as temporary expedient.

    State can be 'ERROR', 'CONNECTING', 'CONNECTED', 'DISCONNECTING',
    'DISCONNECTED'.
    """)
    class QuarkRuntimeWSActor extends WSActor, WSHandler {
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

        QuarkRuntimeWSActor(String url, Actor originator, PromiseResolver factory) {
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
            long now = Context.runtime().now();
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
            Context.runtime().open(self.url, self);
        }

        void onMessage(Actor origin, Object message) {
            logPrologue("ws onMessage (actor message)");
            logTS("   message is from " + origin.toString());
            if (message.getClass().id == "quark.String"
                && self.state == "CONNECTED") {
                logTS("   send-ish, message is: " + message.toString());
                self.socket.send(?message);
                return;
            }
            if (message.getClass().id == "mdk_runtime.WSClose"
                && self.state == "CONNECTED") {
                logTS("   close-ish, switching to DISCONNECTING state");
                self.state = "DISCONNECTING";
                self.socket.close();
                return;
            }
            logger.warn("ws onMessage got unhandled message: " +
                        message.getClass().id + " in state " + self.state);
        }

        // WSHandler
        void onWSConnected(WebSocket socket) {
            logPrologue("onWSConnected");
            if (self.state == "ERROR") {
                logTS("Connection event after error event!");
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

    @doc("""
    WebSocket that uses current Quark runtime as temporary expedient.
    """)
    class QuarkRuntimeWebSockets extends WebSockets {
        // XXX need better story for logging; perhaps integrate MDK Session with
        // the MessageDispatcher?
        Logger logger = new Logger("protocol");

        MessageDispatcher dispatcher;
        List<WSActor> connections = [];

        mdk_runtime.promise.Promise connect(String url, Actor originator) {
            logger.debug(originator.toString() + "requested connection to "
                         + url);
            PromiseResolver factory =  new PromiseResolver(self.dispatcher);
            QuarkRuntimeWSActor actor = new QuarkRuntimeWSActor(url, originator, factory);
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

    class _ScheduleTask extends Task {
        QuarkRuntimeTime timeService;
        Actor requester;
        String event;

        _ScheduleTask(QuarkRuntimeTime timeService, Actor requester, String event) {
            self.timeService = timeService;
            self.requester = requester;
            self.event = event;
        }

        void onExecute(Runtime runtime) {
            timeService.dispatcher.tell(
                self.timeService, new Happening(self.event, self.timeService.time()), self.requester);
        }
    }

    @doc("""
    Temporary implementation based on Quark runtime, until we have native
    implementation.
    """)
    class QuarkRuntimeTime extends Time, SchedulingActor {
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
            if (seconds == 0.0) {
                // Reduce chances of reentrant scheduled event; shouldn't be
                // necessary in non-threaded versions.
                seconds = 0.1;
            }
            Context.runtime().schedule(new _ScheduleTask(self, origin, sched.event), seconds);
        }

        float time() {
            float milliseconds = Context.runtime().now().toFloat();
            return milliseconds / 1000.0;
        }
    }

    @doc("Use real environment variables.")
    class RealEnvVars extends EnvironmentVariables {
        EnvironmentVariable var(String name) {
            return new EnvironmentVariable(name,
                                           Environment.getEnvironment()[name]);
        }
    }

    @doc("Create a MDKRuntime with the default configuration and start its actors.")
    MDKRuntime defaultRuntime() {
        //logging.makeConfig().setLevel("DEBUG").configure();
        MDKRuntime runtime = new MDKRuntime();
        runtime.dependencies.registerService("envvar", new RealEnvVars());
        QuarkRuntimeTime timeService = new QuarkRuntimeTime();
        QuarkRuntimeWebSockets websockets = new QuarkRuntimeWebSockets();
        runtime.dependencies.registerService("time", timeService);
        runtime.dependencies.registerService("schedule", timeService);
        runtime.dependencies.registerService("websockets", websockets);
        mdk_runtime.files.FileActor fileActor = new mdk_runtime.files.FileActorImpl(runtime);
        runtime.dependencies.registerService("files", fileActor);
        runtime.dispatcher.startActor(timeService);
        runtime.dispatcher.startActor(websockets);
        runtime.dispatcher.startActor(fileActor);
        return runtime;
    }

}
