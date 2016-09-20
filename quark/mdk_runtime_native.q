quark 1.0;

package datawire_mdk_runtime 2.0.12;

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
        Logger logger = new Logger("protocol");
        WebSocket socket;
	PromiseResolver factory;
	Actor originator;
	MessageDispatcher dispatcher;
	String state = "CONNECTING";

	NativeWSActor(Actor originator, PromiseResolver factory) {
	    self.originator = originator;
	    self.factory = factory;
	}

	// Actor
	void onStart(MessageDispatcher dispatcher) {
	    self.dispatcher = dispatcher;
	}

	void onMessage(Actor origin, Object message) {
	    if (message.getClass().id == "quark.String"
		&& self.state == "CONNECTED") {
		self.socket.send(?message);
		return;
	    }
	    if (message.getClass().id == "mdk_runtime.WSClose"
		&& self.state == "CONNECTED") {
		self.state = "DISCONNECTING";
		self.socket.close();
		return;
	    }
	}

	// WSHandler
	void onWSConnected(WebSocket socket) {
	    logger.debug("onWSConnected, current state " + self.state +
			 "originator: " + self.originator.toString() + " and I am " +
			 self.toString());
	    if (self.state == "ERROR") {
		logger.debug("Connection event after error event!");
		return;
	    }
	    self.state = "CONNECTED";
	    self.socket = socket;
	    self.factory.resolve(self);
	}

	void onWSError(WebSocket socket, WSError error) {
	    logger.debug("onWSError, current state " + self.state +
			 "originator: " + self.originator.toString());
	    if (self.state == "CONNECTING") {
		logger.error("Error connecting to WebSocket: " + error.toString());
                self.state = "ERROR";
		self.factory.reject(new WSConnectError(error.toString()));
		return;
	    }
	    logger.error("WebSocket error: " + error.toString());
	}

	void onWSMessage(WebSocket socket, String message) {
	    logger.debug("onWSMessage, current state: " + self.state +
			 "originator: " + self.originator.toString());
	    self.dispatcher.tell(self, new WSMessage(message), self.originator);
	}

	void onWSFinal(WebSocket socket) {
	    logger.debug("onWSFinal, current state " + self.state +
			 "originator: " + self.originator.toString());
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
	Logger logger = new Logger("protocol");

	MessageDispatcher dispatcher;
        List<WSActor> connections = [];

	mdk_runtime.promise.Promise connect(String url, Actor originator) {
	    logger.debug(originator.toString() + "requested connection to "
			 + url);
	    PromiseResolver factory = new PromiseResolver(self.dispatcher);

	    NativeWSActor actor = new NativeWSActor(originator, factory);
            connections.add(actor);
	    self.dispatcher.startActor(actor);
	    _connect(url, actor);
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
            if (seconds == 0.0) {
                // Reduce chances of reentrant scheduled event; shouldn't be
                // necessary in non-threaded versions.
                seconds = 0.001;
            }
	    _schedule(new _ScheduleCallable(self, origin, sched.event), seconds);
	}

	float time() {
            return _now();
	}
    }

    macro String _env_get(String name)
        $java{($name)}
        $py{native.env_get($name)}
        $js{native.env_get($name)}
        $rb{($name)}
    ;

    @doc("Environment variables via native path.")
    class NativeEnvVars extends EnvironmentVariables {
        EnvironmentVariable var(String name) {
            return new EnvironmentVariable(name, _env_get(name));
        }
    }

    macro bool isJava() $py{False} $js{false} $java{true} $rb{false};
    macro bool isRuby() $py{False} $js{false} $java{false} $rb{true};

    @doc("Create a MDKRuntime with the default configuration and start its actors.")
    MDKRuntime defaultRuntime() {
	MDKRuntime runtime = new MDKRuntime();

        EnvironmentVariables envVars;
        Time timeService;
        SchedulingActor schedActor;
        WebSockets websockets;
        if (isJava() || isRuby()) {
            envVars = new RealEnvVars();
            timeService = new QuarkRuntimeTime();
            schedActor = ?timeService;
            websockets = new QuarkRuntimeWebSockets();
        } else {
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
