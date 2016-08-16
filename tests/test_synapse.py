"""
Tests for Synapse DiscoverySource support.
"""

from __future__ import absolute_import

from unittest import TestCase, SkipTest
from shutil import rmtree
from tempfile import mkdtemp
from json import dumps
import os

from mdk_synapse import Synapse
from .common import fake_runtime
from mdk_discovery import Discovery, Node


class SynapseTests(TestCase):
    """Tests for Synapse."""

    def setUp(self):
        self.runtime = fake_runtime()
        self.disco = Discovery(self.runtime)
        self.runtime.dispatcher.startActor(self.disco)

        self.directory = mkdtemp()
        self.addCleanup(lambda: rmtree(self.directory))
        self.synapse = Synapse(self.directory).create(self.disco, self.runtime)
        self.runtime.dispatcher.startActor(self.synapse)

    def pump(self):
        """Deliver file-change events to Synapse."""
        # Current implementation polls every 5 seconds; later implementation may
        # switch to inotify in which case this will have to change.
        sched = self.runtime.getScheduleService()
        sched.advance(5.0)
        sched.pump()

    def write(self, service, values):
        """Write a service as JSON to disk."""
        with open(os.path.join(self.directory, service), "w") as f:
            values = [d.copy() for d in values]
            for d in values:
                # There can be other values in the JSON:
                d["extra"] = 123
            f.write(dumps(values))

    def remove(self, service):
        """Remove a service JSON file."""
        os.remove(os.path.join(self.directory, service))

    def node(self, service, host, port):
        """Create a Node."""
        node = Node()
        node.service = service
        node.address = "%s:%d" % (host, port)
        node.version = "1.0"
        #node.properties = {"host": host, "port": port, "extra": 123}
        return node

    def assertNodesEqual(self, first, second):
        """Assert two lists of Nodes have the same items (regardless of order)."""
        def get_attrs(l):
            result = []
            for n in l:
                result.append((n.service, n.address, n.version, n.properties))
            return result
        self.assertItemsEqual(get_attrs(first), get_attrs(second))

    def test_newFile(self):
        """A new file in the correct format updates Discovery."""
        self.write("service1.json", [{"host": "host1", "port": 123},
                                     {"host": "host2", "port": 124}])
        self.write("service2.json", [])
        self.pump()
        self.assertNodesEqual(
            self.disco.knownNodes("service1"),
            [self.node("service1", "host1", 123),
             self.node("service1", "host2", 124)])

    def test_changedFile(self):
        """A change to a file updates Discovery."""
        self.write("service1.json", [{"host": "host1", "port": 123},
                                     {"host": "host2", "port": 124}])
        self.pump()
        self.write("service1.json", [{"host": "host3", "port": 125},
                                     {"host": "host4", "port": 126}])
        self.pump()
        self.assertNodesEqual(
            self.disco.knownNodes("service1"),
            [self.node("service1", "host3", 125),
             self.node("service1", "host4", 126)])

    def test_removedFile(self):
        """A removed file updates Discovery."""
        self.write("service1.json", [{"host": "host1", "port": 123},
                                     {"host": "host2", "port": 124}])
        self.pump()
        self.remove("service1.json")
        self.pump()
        self.assertNodesEqual(self.disco.knownNodes("service1"), [])

    def test_badFormat(self):
        """An unreadable file leaves Discovery unchanged."""
        raise SkipTest("Not possible until we fix https://github.com/datawire/quark/issues/246")
        with open(os.path.join(self.directory, "service2.json"), "w") as f:
            f.write("this is not json")
        self.pump()
        self.assertNodesEqual(self.disco.knownNodes("service2"), [])

    def test_unexpectedFilename(self):
        """Files that don't end with '.json' are ignored."""
        self.write("service1.abcd", [{"host": "host1", "port": 123},
                                     {"host": "host2", "port": 124}])
        self.pump()
        self.assertNodesEqual(self.disco.knownNodes("service1"), [])
