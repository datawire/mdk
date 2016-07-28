from unittest import TestCase

from actors.core import MessageDispatcher
from actors.promise import PromiseResolver


class RecordingActor(object):
    """
    An actor that records operations.

    Messages can be forwarded to another actor, but we ensure no infinite
    recursion.
    """
    def __init__(self, name, record, destination):
        self.name = name
        self.record = record
        self.destination = destination
        self.received = set()

    def onStart(self, dispatcher):
        self.dispatcher = dispatcher

    def onMessage(self, origin, message):
        isNew = message not in self.received
        self.received.add(message)
        prefix = "{} received {} from {}: ".format(self.name, message, origin.name)
        self.record.append(prefix + "start")
        # Make sure we don't get into infinite recursion:
        if self.destination is not None and isNew:
            self.record.append("{} sent {} to {}".format(self.name, message, self.destination.name))
            self.dispatcher.tell(self, message, self.destination)
        self.record.append(prefix + "end")


class StartingActor(object):
    """
    An actor that sends a message on start.
    """
    def __init__(self):
        self.record = []

    def onStart(self, dispatcher):
        self.record.append("start started")
        dispatcher.tell(self, "hello", self)
        self.record.append("start finished")

    def onMessage(self, origin, message):
        self.record.append(message)


class Callback(object):
    def __init__(self, record):
        self.record = record

    def call(self, arg):
        self.record.append("callback: " + arg)


class PromiseActor(object):
    """
    An actor that resolves a Promise on message receiption.
    """
    def __init__(self):
        self.record = []

    def onStart(self, dispatcher):
        self.dispatcher = dispatcher

    def onMessage(self, origin, message):
        self.record.append("start")
        resolver = PromiseResolver(self.dispatcher)
        resolver.promise.andThen(Callback(self.record))
        resolver.resolve("hello")
        self.record.append("end")


class MessageDispatcherTests(TestCase):
    """
    Tests for MessageDispatcher.
    """
    def test_no_start_reentrancy(self):
        """
        MessageDispatcher does not allow re-entrancy of actor starts.
        """
        dispatcher = MessageDispatcher()
        actor = StartingActor()
        dispatcher.startActor(actor)
        self.assertEqual(actor.record,
                         ["start started",
                          "start finished",
                          "hello"])

    def test_multiple_tell(self):
        """
        Calling tell() multiple times still delivers messages.
        """
        dispatcher = MessageDispatcher()
        actor = StartingActor()
        dispatcher.startActor(actor)
        actor.record = []
        dispatcher.tell(actor, "what's", actor)
        dispatcher.tell(actor, "up", actor)
        self.assertEqual(actor.record, ["what's", "up"])

    def test_no_message_reentrancy(self):
        """
        MessageDispatcher does not allow re-entrancy of message delivery.
        """
        record = []
        Origin = RecordingActor("Origin", record, None)
        A = RecordingActor("A", record, None)
        B = RecordingActor("B", record, A)
        A.destination = B
        dispatcher = MessageDispatcher()
        dispatcher.startActor(A)
        dispatcher.startActor(B)
        dispatcher.tell(Origin, 123, A)
        self.assertEqual(
            record, [
                # A receives first message, sends on to B
                'A received 123 from Origin: start',
                'A sent 123 to B',
                'A received 123 from Origin: end',
                # *After* it is done, B receives its message:
                'B received 123 from A: start',
                'B sent 123 to A',
                'B received 123 from A: end',
                # And only after *that* is done, A receives its message:
                'A received 123 from B: start',
                'A received 123 from B: end'])

    def test_no_promise_reentrancy(self):
        """
        MessageDispatcher does not allow re-entrancy of Promise callbacks.
        """
        dispatcher = MessageDispatcher()
        actor = PromiseActor()
        dispatcher.startActor(actor)
        dispatcher.tell(actor, "hello", actor)
        self.assertEqual(actor.record, ["start", "end", "callback: hello"])
