quark 1.0;

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

        Return either a result of some sort or a Promise that resolves to the result..
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
	_AskRequest request = new _AskRequest(msg, destination.getDispatcher().startActor(router));
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

    XXX This design is buggy: non-reentrancy isn't actually guaranteed if the
    response to the ask() is a Promise.
    """)
    class _AskRouter extends Actor {
	PromiseFactory factory = new PromiseFactory();

	Object _addResult(bool ignore, _AskResponse response) {
	    // We're done, shut down this Actor:
	    response.askRouter.stop();
	    return response.response;
	}

	void onMessage(ActorRef origin, Message msg) {
	    _AskResponse response = ?msg;
	    // XXX not sure if PromiseFactory.resolve() with a Promise DTRT,
	    // so do workaround in case it doesn't:
	    self.factory.promise.andThen(bind(self, "_addResult", [response]));
	    self.factory.resolve(true);
	}
    }

}}
