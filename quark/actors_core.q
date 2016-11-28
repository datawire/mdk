quark 1.0;

import quark.concurrent;

/*
Core implementation of actors.
*/

namespace mdk_runtime {
namespace actors {

    @doc("A store of some state. Emits events and handles events.")
    interface Actor {
        @doc("The Actor should start operating.")
        void onStart(MessageDispatcher dispatcher);

        @doc("The Actor should begin shutting down.")
        void onStop() {}

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

        String toString() {
            return ("{" + origin.getClass().id + "->" + destination.getClass().id
                    + ": " + msg.getClass().id + "}");
        }
    }

    @doc("Start or stop an Actor.")
    class _StartStopActor extends _QueuedMessage {
        Actor actor;
        MessageDispatcher dispatcher;
        bool start;

        _StartStopActor(Actor actor, MessageDispatcher dispatcher, bool start) {
            self.actor = actor;
            self.dispatcher = dispatcher;
            self.start = start;
        }

        String toString() {
            String result = "stopping";
            if (self.start) {
                result = "starting";
            }
            return result + " " + self.actor.toString();
        }

        void deliver() {
            if (self.start) {
                self.actor.onStart(self.dispatcher);
            } else {
                self.actor.onStop();
            }
        }
    }


    interface _CallLater {
        void schedule(Task t);
        void runAll();
    }

    class _QuarkRuntimeLaterCaller extends _CallLater {
        void schedule(Task t) {
            Context.runtime().schedule(t, 0.0);
        }

        void runAll() { }
    }

    class _ManualLaterCaller extends _CallLater {
        List<Task> tasks = [];

        void schedule(Task t) {
            tasks.add(t);
        }

        void doNext() {
            Task t = tasks.remove(0);
            t.onExecute(null);
        }

        bool hasNext() {
            return tasks.size() > 0;
        }

        void runAll() {
            while (hasNext()) {
                doNext();
            }
        }
    }

    @doc("""
    Manage a group of related Actors.

    Each Actor should only be started and used by one MessageDispatcher.

    Reduce accidental re-entrancy by making sure messages are run asynchronously.
    """)
    class MessageDispatcher extends Task {
        _CallLater callLater = null;
        Logger logger = new Logger("actors");
        List<_QueuedMessage> _queued = [];
        bool _delivering = false;
        Lock _lock = new Lock(); // Will become unnecessary once we abandon Quark runtime

        MessageDispatcher(_CallLater callLater) {
            self.callLater = callLater;
        }

        @doc("Queue a message from origin to destination, and trigger delivery if necessary.")
        void tell(Actor origin, Object message, Actor destination) {
            _InFlightMessage inFlight = new _InFlightMessage(origin, message, destination);
            self._queue(inFlight);
        }

        @doc("Start an Actor.")
        void startActor(Actor actor) {
            self._queue(new _StartStopActor(actor, self, true));
        }

        @doc("Stop an Actor.")
        void stopActor(Actor actor) {
            self._queue(new _StartStopActor(actor, self, false));
        }

        bool _callQueuedMessage(Object ignore, _QueuedMessage message) {
            message.deliver();
            return true;
        }

        @doc("Queue a message for delivery.")
        void _queue(_QueuedMessage inFlight) {
            logger.debug("Queued " + inFlight.toString());
            self._lock.acquire();
            self._queued.add(inFlight);
            if (!self._delivering) {
                self._delivering = true;
                callLater.schedule(self);
            }
            self._lock.release();
        }

        @doc("Are there any messages waiting to be delivered?")
        bool queued() {
            self._lock.acquire();
            bool result = self._delivering;
            self._lock.release();
            return result;
        }

        @doc("Causes message delivery to occur when using manual CallLater")
        void pump() {
            while (self.queued()) {
                self.callLater.runAll();
            }
        }

        void onExecute(Runtime runtime) {
            self._lock.acquire();

            // Delivering messages may cause additional ones to be queued:
            while (self._queued.size() > 0) {
                List<_QueuedMessage> toDeliver = self._queued;
                self._queued = [];

                self._lock.release();
                int idx = 0;
                while (idx < toDeliver.size()) {
                    logger.debug("Delivering " + toDeliver[idx].toString());
                    UnaryCallable deliver = bind(self, "_callQueuedMessage", [toDeliver[idx]]);
                    bool success = ?Context.runtime().callSafely(deliver, false);
                    if (!success) {
                        logger.warn("FAILURE when delivering " + toDeliver[idx].toString());
                    }
                    idx = idx + 1;
                }
                self._lock.acquire();
            }
            self._delivering = false;
            self._lock.release();
        }
    }

}}
