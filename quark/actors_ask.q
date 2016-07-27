quark 1.0;

import quark.reflect;
import actors.core;

namespace actors {
namespace ask {

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

        Return either a result of some sort or a Promise that resolves to the result.
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

	bool _respond(Object result, AskActor destination) {
	    askRouter.tell(destination, new _AskResponse(result, askRouter));
	    return true;
	}

	@doc("Deliver the message, send the response to the _AskRouter.")
	void deliver(ActorRef origin, AskActor destination) {
	    Object result = destination.onAsk(origin, self.wrapped);
	    if (Class.get("quark.Promise").hasInstance(result)) {
		// In order to preserve non-reentrancy, we want to make sure we
		// only send the message once we have a result. Sending a
		// message with an asynchronous result like a Promise would mean
		// that the Promise might fire and cause reentrancy in code that
		// is then run.
		Promise resultPromise = ?result;
		resultPromise.andThen(bind(self, "_respond", [destination]));
		return;
	    }
	    // Synchronous result, can deliver response immediately:
	    self._respond(result, destination);
	}
    }

    @doc("Wraps a resolved response to an ask(), i.e. anything but a Promise.")
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
	_AskRequest request = new _AskRequest(msg, destination.getDispatcher().startActor(router));
	destination.tell(origin, request);
	return router.factory.promise;
    }

    @doc("Handle messages that are ask() messages. See AskActor for usage.")
    bool deliverAsks(ActorRef origin, Message msg, AskActor destination) {
	if (quark.reflect.Class.get("actors._AskRequest").hasInstance(msg)) {
	    _AskRequest request = ?msg;
	    request.deliver(origin, destination);
	    return true;
	}
	return false;
    }

    @doc("""
    Handle ask() replies by resolving the appropriate Promise.
    """)
    class _AskRouter extends Actor {
	PromiseFactory factory = new PromiseFactory();

	void onMessage(ActorRef origin, Message msg) {
	    _AskResponse response = ?msg;
	    self.factory.resolve(response.response);
	    response.askRouter.stop(); // All done with this actor
	}
    }

}}
