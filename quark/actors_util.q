quark 1.0;

namespace actors {
namespace util {

    @doc("Deliver a single Message to multiple Actors.")
    class Multicast extends Actor {
	List<ActorRef> destinations;

	Multicast(List<ActorRef> destinations) {
	    self.destinations = destinations;
	}

	void onMessage(ActorRef origin, Message message) {
	    long idx = 0;
	    while (idx < destinations.size()) {
		destinations[idx].tell(origin.getActor(), message);
		idx = idx + 1;
	    }
	}
    }

}}
