quark 1.0;

package datawire_dependency 1.0.0;

use actors.q;
import actors.core;

@doc("""
""")
namespace dependency {
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
    }
}
