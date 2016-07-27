quark 1.0;

import quark.concurrent;

namespace actors {
namespace core {

    @doc("A message.")
    interface Message {}

    @doc("Indicates inability to respond a message.")
    class Unhandled extends Message {}

    @doc("A store of some state. Emits events and handles events.")
    interface Actor {
	@doc("Called on incoming one-way message from another actor sent via tell().")
	void onMessage(ActorRef origin, Message message);
    }

    @doc("""A reference to an actor.

    Should not be created directly. Instead, use MessageDispatcher.startActor().
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

	@doc("Asynchronously send a message to the actor.")
	void tell(Actor origin, Message msg) {
	    self._dispatcher._tell(origin, msg, self);
	}

	@doc("Stop the Actor. Should only be called once.")
	void stop() {
	    self._dispatcher._stopActor(self._actor);
	}
    }

    @doc("A message that queued for delivery by a MessageDispatcher.")
    class _InFlightMessage {
	ActorRef origin;
	Message msg;
	ActorRef destination;

	_InFlightMessage(ActorRef origin, Message msg, ActorRef destination) {
	    self.origin = origin;
	    self.msg = msg;
	    self.destination = destination;
	}

	@doc("Deliver the message.")
	void deliver() {
	    Actor underlyingDestination = self.destination.getActor();
	    underlyingDestination.onMessage(self.origin, self.msg);
	}
    }

    @doc("""
    Manage a group of related Actors.

    Each Actor should only be started and used by one MessageDispatcher.

    Ensure no re-entrancy by making sure message are run asynchronously.
    """)
    class MessageDispatcher {
	List<_InFlightMessage> _queued = [];
	bool _delivering = false;
	Lock _lock = new Lock(); // Will become unnecessary once we abandon Quark runtime
	Map<Actor,ActorRef> _actors = {};

	@doc("Start an actor, returning the ActorRef for communicating with it.")
	ActorRef startActor(Actor actor) {
	    if (self._actors.contains(actor)) {
		panic("Actor already started.");
	    }
	    ActorRef result = new ActorRef(self, actor);
	    self._actors[actor] = result;
	    return result;
	}

	@doc("Stop an actor.")
	void _stopActor(Actor actor) {
	    self._actors.remove(actor);
	}

	@doc("Queue a message from origin to destination, and trigger delivery if necessary.")
	void _tell(Actor origin, Message message, ActorRef destination) {
	    if (!self._actors.contains(origin)) {
		self._lock.release();
		panic("Origin actor not started!");
	    }
	    ActorRef originRef = self._actors[origin];
	    _InFlightMessage inFlight = new _InFlightMessage(originRef, message, destination);
	    self._lock.acquire();
	    self._queued.add(inFlight);
	    self._lock.release();
	    if (self._delivering) {
		// Someone higher in call stack is doing delivery, they'll deal
		// with it.
		return;
	    }
	    self._lock.acquire();
	    self._delivering = true;
	    // Delivering messages may cause additional ones to be queued:
	    while (self._queued.size() > 0) {
		List<_InFlightMessage> toDeliver = self._queued;
		self._queued = [];

		self._lock.release();
		long idx = 0;
		while (idx < toDeliver.size()) {
		    toDeliver[idx].deliver();
		    idx = idx + 1;
		}
		self._lock.acquire();
	    }
	    self._delivering = false;
	    self._lock.release();
	}
    }

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
