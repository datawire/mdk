quark 1.0;

import quark.concurrent;

namespace actors {

    @doc("A message.")
    interface Message {}

    @doc("Indicates inability to respond a message.")
    class Unhandled extends Message {}

    @doc("A store of some state. Emits events and handles events.")
    interface Actor {
	@doc("Called on incoming one-way message from another actor sent via tell().")
	void onMessage(ActorRef origin, Message message);

	@doc("""
        Called on incoming ask() request from another actor that requires a response.

        Return either a Message or a Promise that resolves to a Message.
        """)
	Object onAsk(ActorRef origin, Message message);
    }

    @doc("Start an actor, returning the ActorRef for communicating with it.")
    ActorRef startActor(ActorRef parent, Actor theActor) {
	return parent.getDispatcher()._startActor(theActor);
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

	Actor getActor() {
	    return self._actor;
	}

	MessageDispatcher getDispatcher() {
	    return self._dispatcher;
	}

	@doc("Deliver a message to the actor.")
	void tell(Actor origin, Message msg) {
	    self._dispatcher.tell(origin, msg, self, false);
	}

	@doc("Deliver a request to the actor, get back Promise of a response.")
	Promise ask(Actor origin, Message msg) {
	    return self._dispatcher.tell(origin, msg, self, true);
	}
    }

    class _InFlightMessage {
	ActorRef origin;
	Message msg;
	ActorRef destination;
	bool responseExpected;
	PromiseFactory response;

	_InFlightMessage(ActorRef origin, Message msg, ActorRef destination, bool responseExpected) {
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
	    Actor underlyingDestination = self.destination.getActor();
	    if (self.responseExpected) {
		Object result = underlyingDestination.onAsk(self.origin, self.msg);
		// XXX not sure if PromiseFactory.resolve() with a Promise DTRT,
		// so do workaround in case it doesn't:
		self.response.promise.andThen(bind(self, "_addResult", [result]));
		self.response.resolve(true);
		return;
	    }
	    underlyingDestination.onMessage(self.origin, self.msg);
	}
    }

    @doc("Ensure no re-entrancy by making sure message are run asynchronously.")
    class MessageDispatcher {
	List<_InFlightMessage> _queued = [];
	bool _delivering = false;
	Lock _lock = new Lock(); // Will become unnecessary once we abandon Quark runtime
	Map<Actor,ActorRef> _actors = {};

	ActorRef _startActor(Actor actor) {
	    if (self._actors.contains(actor)) {
		panic("Actor already started.");
	    }
	    ActorRef result = new ActorRef(self, actor);
	    self._actors[actor] = result;
	    return result;
	}

	@doc("Queue a message from origin to destination, and trigger delivery if necessary.")
	Promise tell(Actor origin, Message message, ActorRef destination, bool responseExpected) {
	    self._lock.acquire();
	    ActorRef originRef = self._actors[origin];
	    _InFlightMessage inFlight = new _InFlightMessage(originRef, message, destination, responseExpected);
	    Promise result = inFlight.response.promise;
	    self._queued.add(inFlight);
	    if (self._delivering) {
		self._lock.release();
		return result;
	    }
	    self._delivering = true;
	    List<_InFlightMessage> toDeliver = self._queued;
	    self._queued = [];

	    long idx = 0;
	    while (idx < toDeliver.size()) {
		toDeliver[idx].deliver();
		idx = idx + 1;
	    }
	    self._lock.release();
	    return result;
	}
    }

    @doc("Deliver a single Message to multiple Actors.")
	class Multicast extends Actor {
	List<ActorRef> destinations;

	Multicast(List<ActorRef> destinations) {
	    self.destinations = destinations;
	}

	Object onAsk(ActorRef origin, Message message) {
	    return new Unhandled();
	}

	void onMessage(ActorRef origin, Message message) {
	    long idx = 0;
	    while (idx < destinations.size()) {
		destinations[idx].tell(origin.getActor(), message);
		idx = idx + 1;
	    }
	}
    }
}
