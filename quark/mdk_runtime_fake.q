quark 1.0;

package datawire_mdk_runtime 2.0.14;

include mdk_runtime_common.q;

import mdk_runtime.actors;
import mdk_runtime.promise;


namespace mdk_runtime {

    @doc("WSActor implementation for testing purposes.")
    class FakeWSActor extends WSActor {
        String url;
        PromiseResolver resolver;
        bool resolved = false;
        MessageDispatcher dispatcher;
        Actor originator;
        List<String> sent = [];
        String state = "CONNECTING";
        int expectIdx = 0;

        FakeWSActor(Actor originator, PromiseResolver resolver, String url) {
            self.url = url;
            self.originator = originator;
            self.resolver = resolver;
        }

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object message) {
            if (message.getClass().id == "quark.String"
                && self.state == "CONNECTED") {
                self.sent.add(?message);
                return;
            }
            if (message.getClass().id == "mdk_runtime.WSClose"
                && self.state == "CONNECTED") {
                self.close();
                return;
            }
        }

        // Testing API:
        @doc("""
        Simulate the remote peer accepting the socket connect.
        """)
        void accept() {
            if (resolved) {
                Context.runtime().fail("Test bug. already accepted");
            } else {
                resolved = true;
                self.state = "CONNECTED";
                self.resolver.resolve(self);
            }
        }

        @doc("Simulate the remote peer rejecting the socket connect.")
        void reject() {
            if (resolved) {
                Context.runtime().fail("Test bug. already accepted");
            } else {
                resolved = true;
                self.resolver.reject(new WSConnectError("connection refused"));
            }
        }

        @doc("""
        Simulate the remote peer sending a text message to the client.
        """)
        void send(String message) {
            if (self.state != "CONNECTED") {
                Context.runtime().fail("Test bug. Can't send when not connected.");
            }
            self.dispatcher.tell(self, new WSMessage(message), originator);
        }

        @doc("""
        Simulate the remote peer closing the socket.
        """)
        void close() {
            if (self.state == "CONNECTED") {
                self.state = "DISCONNECTED";
                self.dispatcher.tell(self, new WSClosed(), originator);
            } else {
                Context.runtime().fail("Test bug. Can't close already closed socket.");
            }
        }

        @doc("""
        Check that a message has been sent via this actor.
        """)
        String expectTextMessage() {
            if (!resolved) {
                Context.runtime().fail("not connected yet");
                return "unreachable";
            }

            if (expectIdx < self.sent.size()) {
                String msg = self.sent[expectIdx];
                expectIdx = expectIdx + 1;
                return msg;
            }
            Context.runtime().fail("no remaining message found");
            return "unreachable";
        }
    }

    @doc("""
    WebSocket implementation for testing purposes.
    """)
    class FakeWebSockets extends WebSockets {
        MessageDispatcher dispatcher;
        List<FakeWSActor> fakeActors = [];

        mdk_runtime.promise.Promise connect(String url, Actor originator) {
            PromiseResolver factory =  new PromiseResolver(self.dispatcher);
            FakeWSActor actor = new FakeWSActor(originator, factory, url);
            self.dispatcher.startActor(actor);
            self.fakeActors.add(actor);
            return factory.promise;
        }

        FakeWSActor lastConnection() {
            return self.fakeActors[self.fakeActors.size() - 1];
        }

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object message) {}
    }

    class _FakeTimeRequest {
        Actor requester;
        String event;
        float happensAt;

        _FakeTimeRequest(Actor requester, String event, float happensAt) {
            self.requester = requester;
            self.event = event;
            self.happensAt = happensAt;
        }
    }

    @doc("Testing fake.")
    class FakeTime extends Time, SchedulingActor {
        float _now = 1000.0;
        Map<long,_FakeTimeRequest> _scheduled = {};
        MessageDispatcher dispatcher;

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
        }

        void onMessage(Actor origin, Object msg) {
            Schedule sched = ?msg;
            _scheduled[_scheduled.keys().size()] = new _FakeTimeRequest(origin, sched.event, self._now + sched.seconds);
        }

        float time() {
            return self._now;
        }

        @doc("Run scheduled events whose time has come.")
        void pump() {
            int idx = 0;
            List<long> keys = self._scheduled.keys();
            while (idx < keys.size()) {
                _FakeTimeRequest request = _scheduled[keys[idx]];
                if (request.happensAt <= self._now) {
                    self._scheduled.remove(keys[idx]);
                    self.dispatcher.tell(self, new Happening(request.event, time()), request.requester);
                }
                idx = idx + 1;
            }
        }

        @doc("Move time forward.")
        void advance(float seconds) {
            self._now = self._now + seconds;
        }

        @doc("Number of scheduled events.")
        int scheduled() {
            return self._scheduled.keys().size();
        }
    }

    @doc("Testing fake for EnvironmentVariables.")
    class FakeEnvVars extends EnvironmentVariables {
        Map<String,String> env = {};

        void set(String name, String value) {
            self.env[name] = value;
        }

        EnvironmentVariable var(String name) {
            String value = null;
            if (self.env.contains(name)) {
                value = self.env[name];
            }
            return new EnvironmentVariable(name, value);
        }
    }

    MDKRuntime fakeRuntime() {
        MDKRuntime runtime = new MDKRuntime();
        runtime.dependencies.registerService("envvar", new FakeEnvVars());
        FakeTime timeService = new FakeTime();
        FakeWebSockets websockets = new FakeWebSockets();
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
