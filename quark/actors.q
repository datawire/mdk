import stdlib;

namespace actors {

    @doc("A message.")
    interface Message {}

    @doc("Indicates no response to a message.")
    class _NoResponse {}
    var NoResponse = new _NoResponse();

    @doc("A store of some state. Emits events and handles events.")
    interface Actor {
	@doc("""\
        Called on incoming message from another actor.

        Can return an answer the event, by returning an event or a Promise of an
        event. If no answer is needed it should return NoResponse.
        """)
	Object onMessage(ActorRef origin, Event event);
    }

    @doc("Start an actor, returning the ActorRef for communicating with it.")
    ActorRef startActor(ActorRef parent, Actor theActor) {
	// XXX no way to catch multiple starts.
	return new ActorRef(parent.getDispatcher(), theActor);
    }

    @doc("""A reference to an actor.

    Typically not created directly. Instead, use startActor().
    """)
    class ActorRef {
	Actor _actor;
	MessageDispatcher _dispatcher;

	ActorRef(MessageDispatcher dispatcher, Actor actor) {
	    self._dispatcher = dispatcher;
	    self._actor = actor;
	}

	MessageDispatcher getDispatcher() {
	    return self._dispatcher;
	}

	@doc("Deliver a message to the actor.")
	void tell(ActorRef origin, Message msg) {
	    self._dispatcher.tell(origin, msg, self._actor);
	}
    }

    class _InFlightMessage {
	ActorRef origin;
	Message msg;
	Actor destination;

	_InFlightMessage(ActorRef origin, Message msg, Actor destination) {
	    self.origin = origin;
	    self.msg = msg;
	    self.destination = destination;
	}

       Object deliver() {
	    return self.destination.onMessage(self.origin, self.msg);
	}
    }

    @doc("Ensure no re-entrancy by making sure message are run asynchronously.")
    class MessageDispatcher {
	List<_MessageInFlight> queued = [];
	bool _delivering = false;
	Mutex _lock; // Will become unnecessary once we abandon Quark runtime

	@doc("Deliver an event from origin to destination.")
	void tell(ActorRef origin, Message message, Actor destination) {
	    self._lock.acquire();
	    self.queued.add(new _MessageInFlight(origin, event, destination));
	    if (self._delivering) {
		self._lock.release();
		return;
	    }
	    self._delivering = true;
	    List<_MessageInFlight> toDeliver = self._queued;
	    self._queued = [];
	    self._lock.release();

	    long idx = 0;
	    while (idx < toDeliver.size()) {
		Object result = toDeliver[idx].deliver();
		if (result != NoResponse) {
		    // Once ask() is implemented returning NoResponse on ask()
		    // is a bug in user code, as is returning something else for
		    // tell().
		    panic("ask() not implemented yet.");
		}
		idx = idx + 1l;
	    }
	    self._lock.release();
	}
    }

    @doc("Deliver a single Message to multiple Actors.")
    class Multicast implements Actor {
	List<ActorRef> destinations;

	Multicast(List<ActorRef> destinations) {
	    self.destinations = destinations;
	}

	Object onMesssage(ActorRef origin, Message message) {
	    long idx = 0;
	    while (idx < destinations.size()) {
		destinations[idx].onMessage(origin, message);
		idx = idx + 1l;
	    }
	    return NoResponse;
	}
    }
}
