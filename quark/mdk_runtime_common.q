quark 1.0;

include actors_core.q;
include actors_promise.q;
include mdk_runtime_files.q;

import mdk_runtime.actors;
import mdk_runtime.promise;

namespace mdk_runtime {

    @doc("Trivial dependency injection setup.")
    class Dependencies {
        Map<String,Object> _services = {};

        @doc("Register a service object.")
        void registerService(String name, Object service) {
            if (self._services.contains(name)) {
                panic("Can't register service '" + name + "' twice.");
            }
            self._services[name] = service;
        }

        @doc("Look up a service by name.")
        Object getService(String name) {
            if (!self._services.contains(name)) {
                panic("Service '" + name + "' not found!");
            }
            return self._services[name];
        }

        @doc("Return whether the service exists.")
        bool hasService(String name) {
            return self._services.contains(name);
        }

    }

    @doc("""
    Runtime environment for a particular MDK instance.

    Required registered services:
    - 'time': A provider of mdk_runtime.Time;
    - 'schedule': Implements the mdk_runtime.ScheduleActor actor protocol.
    - 'websockets': A provider of mdk_runtime.WebSockets.
    """)
    class MDKRuntime {
        Dependencies dependencies = new Dependencies();
        MessageDispatcher dispatcher = null;

        @doc("Return Time service.")
        Time getTimeService() {
            return ?self.dependencies.getService("time");
        }

        @doc("Return Schedule service.")
        Actor getScheduleService() {
            return ?self.dependencies.getService("schedule");
        }

        @doc("Return WebSockets service.")
        WebSockets getWebSocketsService() {
            return ?self.dependencies.getService("websockets");
        }

        @doc("Return File service.")
        mdk_runtime.files.FileActor getFileService() {
            return ?self.dependencies.getService("files");
        }

        @doc("Return EnvironmentVariables service.")
        EnvironmentVariables getEnvVarsService() {
            return ?self.dependencies.getService("envvar");
        }

        @doc("Stop all Actors that are started by default (i.e. files, schedule).")
        void stop() {
            self.dispatcher.stopActor(getFileService());
            self.dispatcher.stopActor(self.getScheduleService());
            self.dispatcher.stopActor(self.getWebSocketsService());
        }
    }

    @doc("""
    Return current time.
    """)
    interface Time {
        @doc("""
        Return the current time in seconds since the Unix epoch.
        """)
        float time();
    }

    @doc("""
    An actor that can schedule events.

    Accepts Schedule messages and send Happening events to originator at the
    appropriate time.
    """)
    interface SchedulingActor extends Actor {}

    @doc("""
    Service that can open new WebSocket connections.

    When stopped it should close all connections.
    """)
    interface WebSockets extends Actor {
        @doc("""
        The Promise resolves to a WSActor or WSConnectError. The originator will
        receive messages.
        """)
        mdk_runtime.promise.Promise connect(String url, Actor originator);
    }

    @doc("Connection failed.")
    class WSConnectError extends Error {
        String toString() {
            return "<WSConnectionError: " + super.toString() + ">";
        }
    }

    @doc("""
    Actor representing a specific WebSocket connection.

    Accepts String and WSClose messages, sends WSMessage and WSClosed
    messages to the originator of the connection (Actor passed to
    WebSockets.connect()).
    """)
    interface WSActor extends Actor {}

    @doc("A message was received from the server.")
    class WSMessage {
        String body;

        WSMessage(String body) {
            self.body = body;
        }
    }

    @doc("Tell WSActor to close the connection.")
    class WSClose {}

    @doc("Notify of WebSocket connection having closed.")
    class WSClosed {}

    @doc("""
    Please send me a Happening message with given event name in given number of
    seconds.
    """)
    class Schedule {
        String event;
        float seconds;

        Schedule(String event, float seconds) {
            self.event = event;
            self.seconds = seconds;
        }
    }

    @doc("A scheduled event is now happening.")
    class Happening {
        String event;
        float currentTime;

        Happening(String event, float currentTime) {
            self.event = event;
            self.currentTime = currentTime;
        }
    }

    @doc("EnvironmentVariable is a Supplier of Strings that come from the environment.")
    class EnvironmentVariable {
        String variableName;
        String _value;

        EnvironmentVariable(String variableName, String value) {
            self.variableName = variableName;
            self._value = value;
        }

        bool isDefined() {
            return get() != null;
        }

        String get() {
            return self._value;
        }

        String orElseGet(String alternative) {
            String result = get();
            if (result != null) {
                return result;
            }
            else {
                return alternative;
            }
        }
    }

    @doc("Inspect process environment variables.")
    interface EnvironmentVariables {
        @doc("Return an EnvironmentVariable instance for the given var.")
        EnvironmentVariable var(String name);
    }

}
