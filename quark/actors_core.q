quark 1.0;

import quark.concurrent;

/*
Core implementation of actors.
*/

namespace actors {
namespace core {

    @doc("A store of some state. Emits events and handles events.")
    interface Actor {
	@doc("Called when the Actor is started.")
	void onStart(MessageDispatcher dispatcher);

	@doc("Called on incoming one-way message from another actor sent via tell().")
	void onMessage(Actor origin, Object message);
    }

    @doc("A message that can be queued for delivery in a MessageDispatcher.")
    interface _QueuedMessage {
	void deliver();
    }

    @doc("A message that queued for delivery by a MessageDispatcher.")
    class _InFlightMessage extends _QueuedMessage {
	Actor origin;
	Object msg;
	Actor destination;

	_InFlightMessage(Actor origin, Object msg, Actor destination) {
	    self.origin = origin;
	    self.msg = msg;
	    self.destination = destination;
	}

	@doc("Deliver the message.")
	void deliver() {
	    self.destination.onMessage(self.origin, self.msg);
	}
    }

    @doc("Start an Actor.")
    class _StartActor extends _QueuedMessage {
	Actor actor;
	MessageDispatcher dispatcher;

	_StartActor(Actor actor, MessageDispatcher dispatcher) {
	    self.actor = actor;
	    self.dispatcher = dispatcher;
	}

	void deliver() {
	    self.actor.onStart(self.dispatcher);
	}
    }

    @doc("""
    Manage a group of related Actors.

    Each Actor should only be started and used by one MessageDispatcher.

    Reduce accidental re-entrancy by making sure messages are run asynchronously.
    """)
    class MessageDispatcher {
	List<_QueuedMessage> _queued = [];
	bool _delivering = false;
	Lock _lock = new Lock(); // Will become unnecessary once we abandon Quark runtime

	@doc("Queue a message from origin to destination, and trigger delivery if necessary.")
	void tell(Actor origin, Object message, Actor destination) {
	    _InFlightMessage inFlight = new _InFlightMessage(origin, message, destination);
	    self._queue(inFlight);
	}

	@doc("Start an Actor.")
	void startActor(Actor actor) {
	    self._queue(new _StartActor(actor, self));
	}

	@doc("Queue a message for delivery.")
	void _queue(_QueuedMessage inFlight) {
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
		List<_QueuedMessage> toDeliver = self._queued;
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

}}
