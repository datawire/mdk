import stdlib;

namespace actors {

    @doc("A message.")
    interface Message {}

    @doc("Indicates no response to a message.")
    class _NoResponse {}
    var NoResponse = new _NoResponse();

    @doc("A store of some state. Emits events and handles events.")
    interface Actor {
	@doc("Called on incoming one-way message from another actor sent via tell().")
	void onMessage(ActorRef origin, Message message);

	@doc("""\
        Called on incoming ask() request from another actor that requires a response.

        Return either a Message or a Promise that resolves to a Message.
        """)
	Object onAsk(ActorRef origin, Message message);
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
	    self._dispatcher.tell(origin, msg, self._actor, false);
	}

	@doc("Deliver a request to the actor, get back Promise of a response.")
	Promise ask(ActorRef origin, Message msg) {
	    return self._dispatcher.tell(origin, msg, self._actor, true);
	}
    }

    class _InFlightMessage {
	ActorRef origin;
	Message msg;
	Actor destination;
	bool responseExpected;
	PromiseFactory response;

	_InFlightMessage(ActorRef origin, Message msg, Actor destination, bool responseExpected) {
	    self.origin = origin;
	    self.msg = msg;
	    self.destination = destination;
	    self.responseExpected = responseExpected;
	    self.response = new PromiseFactory();
	}

	Object _addResult(bool ignore, Object result) {
	    return result;
	}

	void deliver() {
	    if (self.responseExpected) {
		Object result = self.destination.onAsk(self.origin, self.msg);
		// XXX not sure if PromiseFactory.resolve() with a Promise DTRT,
		// so do workaround in case it doesn't:
		self.response.promise.andThen(bind(self, "_addResult", [result]))
		self.response.resolve(true);
		return;
	    }
	    self.destination.onMessage(self.origin, self.msg);
	}
    }

    @doc("Ensure no re-entrancy by making sure message are run asynchronously.")
    class MessageDispatcher {
	List<_MessageInFlight> queued = [];
	bool _delivering = false;
	Mutex _lock; // Will become unnecessary once we abandon Quark runtime

	@doc("Queue a message from origin to destination, and trigger delivery if necessary.")
	Promise tell(ActorRef origin, Message message, Actor destination, bool responseExpected) {
	    self._lock.acquire();
	    _MessageInFlight inFlight = new _MessageInFlight(origin, event, destination, responseExpected);
	    Promise result = inFlight.response.promise;
	    self.queued.add(inFlight);
	    if (self._delivering) {
		self._lock.release();
		return result;
	    }
	    self._delivering = true;
	    List<_MessageInFlight> toDeliver = self._queued;
	    self._queued = [];

	    long idx = 0;
	    while (idx < toDeliver.size()) {
		toDeliver[idx].deliver();
		idx = idx + 1l;
	    }
	    self._lock.release();
	    return result;
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
