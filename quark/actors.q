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
	    self._dispatcher._tell(origin, msg, self);
	}
    }

    @doc("""
    An actor that can accept ask() queries.

    If you implement this you'll want code that looks like this:

    class MyActor extends AskActor {
        void onMessage(ActorRef origin, Message message) {
            if (deliverAsks(self, origin, message)) {
                return;
            }
            // Handle normal one-way messages here...
        }

	Object onAsk(ActorRef origin, Message message) {
            // Handle ask() messages here, returning a response.
        }
    }
    """)
    interface AskActor extends Actor {
	@doc("""
        Called on incoming ask() request from another actor that requires a response.

        Return either a Message or a Promise that resolves to a Message.
        """)
	Object onAsk(ActorRef origin, Message message);
    }

    @doc("Wrap a message to indicate it's an Ask.")
    class _AskRequest extends Message {
	Message wrapped;
        ActorRef askRouter;

	_AskRequest(Message message, ActorRef askRouter) {
	    self.wrapped = message;
	    self.askRouter = askRouter;
	}
    }

    @doc("Wraps a message or Promise of message.")
    class _AskResponse extends Message {
	Object response;
        ActorRef askRouter;

	_AskResponse(Object response, ActorRef askRouter) {
	    self.response = response;
	    self.askRouter = askRouter;
	}
    }

    @doc("""
    Deliver a request to the actor, get back Promise of a response.

    Note that this is a much more expensive operation than using tell()
    directly.
    """)
    Promise ask(Actor origin, Message msg, ActorRef destination) {
	_AskRouter router = new _AskRouter();
	_AskRequest request = new _AskRequest(msg, destination._dispatcher.startActor(router));
	destination.tell(origin, request);
	return router.factory.promise;
    }

    @doc("Handle messages that are ask() messages. See AskActor for usage.")
    bool deliverAsks(ActorRef origin, Message msg, AskActor destination) {
	if (quark.reflect.Class.get("actors._AskRequest").hasInstance(msg)) {
	    _AskRequest request = ?msg;
	    Object result = destination.onAsk(origin, request.wrapped);
	    request.askRouter.tell(destination, new _AskResponse(result, request.askRouter));
	    return true;
	}
	return false;
    }

    @doc("""
    Handle ask() replies by resolving the appropriate Promise.

    We use this instead of just resolving Promises directly in order to preserve
    the no-reentrancy guarantee.
    """)
    class _AskRouter extends Actor {
	PromiseFactory factory = new PromiseFactory();

	Object _addResult(bool ignore, Object result) {
	    return result;
	}

	void onMessage(ActorRef origin, Message msg) {
	    // XXX not sure if PromiseFactory.resolve() with a Promise DTRT,
	    // so do workaround in case it doesn't:
	    self.factory.promise.andThen(bind(self, "_addResult", [msg]));
	    self.factory.resolve(true);
	}
    }

    class _InFlightMessage {
	ActorRef origin;
	Message msg;
	ActorRef destination;

	_InFlightMessage(ActorRef origin, Message msg, ActorRef destination) {
	    self.origin = origin;
	    self.msg = msg;
	    self.destination = destination;
	}

	void deliver() {
	    Actor underlyingDestination = self.destination.getActor();
	    underlyingDestination.onMessage(self.origin, self.msg);
	}
    }

    @doc("Ensure no re-entrancy by making sure message are run asynchronously.")
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
