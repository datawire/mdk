quark 1.0;

use actors.q;
import actors;

@doc("""
Standard dependency names:

Services, i.e. synchronous blocking APIs:
- 'time': A provider of mdk_runtime.Time;

Actors:
- 'schedule': Implements the mdk_runtime.ScheduleActor actor protocol.
""")
namespace dependency {
    @doc("Trivial dependency injection setup.")
    class Dependencies {
	Map<String,ActorRef> _actors = {};
	Map<String,Object> _services = {};

	@doc("Register a service object.")
	void registerService(String name, Object service) {
	    if (self._services.contains(name)) {
		panic("Can't register service '" + name + "' twice.");
	    }
	    self._services[name] = service;
	}

	@doc("Register an actor reference.")
	void registerActor(String name, ActorRef actor) {
	    if (self._actors.contains(name)) {
		panic("Can't register actor '" + name + "' twice.");
	    }
	    self._actors[name] = actor;
	}

	@doc("Look up an actor by name.")
	ActorRef getActor(String name) {
	    if (!self._actors.contains(name)) {
		panic("Actor '" + name + "' not found!");
	    }
	    return self._actors[name];
	}

	@doc("Look up a service by name.")
	Object getService(String name) {
	    if (!self._services.contains(name)) {
		panic("Service '" + name + "' not found!");
	    }
	    return self._services[name];
	}
    }
}
