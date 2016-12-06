# Copyright 2016 datawire. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# MDK Runtime for Python 2/3


import os
import time

import crochet
from twisted.internet import reactor
from autobahn.twisted.websocket import WebSocketClientProtocol, WebSocketClientFactory, connectWS

import quark


crochet.setup()


def now():
    return time.time()


def schedule(u_callable, delayInSeconds):
    call_callback = lambda arg: reactor.callInThread(quark.callUnaryCallable, u_callable, arg)
    reactor.callFromThread(lambda: reactor.callLater(delayInSeconds, call_callback, None))


def env_get(key):
    return os.environ.get(key, None)


class _QWSCProtocol(WebSocketClientProtocol):

    def onOpen(self):
        assert self.qws, self.qws
        self.qws.is_open = True
        reactor.callInThread(self.qws.handler.onWSConnected, self.qws)

    def onMessage(self, payload, isBinary):
        assert self.qws, self.qws
        if isBinary:
            # Would be: reactor.callInThread(self.qws.handler.onWSBinary, self.qws, Buffer(payload))
            # where Buffer(...) is defined in quark_runtime.py
            return  # FIXME: Silently throw away binary messages
        else:
            reactor.callInThread(self.qws.handler.onWSMessage, self.qws, payload.decode("utf-8"))

    def onClose(self, wasClean, code, reason):
        if wasClean:
            reactor.callInThread(self.qws._respond_closed)        # Closed then Final
        else:
            error = quark.WSError("Error %s in connection to <%s>: %s" % (code, self.qws.url, reason))
            reactor.callInThread(self.qws._respond_error, error)  # Error then Final
        self.qws = None


class _QWSCFactory(WebSocketClientFactory):

    def __init__(self, qws, *args, **kwargs):
        WebSocketClientFactory.__init__(self, *args, **kwargs)
        self.qws = qws

    def buildProtocol(self, addr):
        p = _QWSCProtocol()
        p.factory = self        # Required by autobahn
        p.qws = self.qws        # Allow protocol to pass qws to user handlers
        self.qws.protocol = p   # Allow user code calls to qws.send etc to call into protocol methods
        return p

    def clientConnectionFailed(self, connector, reason):
        error = quark.WSError("Error connecting to URL <%s>: %s" % (self.qws.url, reason))
        reactor.callInThread(self.qws._respond_error, error)  # Error then Final


class _QuarkWebSocket(object):

    def __init__(self, url, handler):
        self.url = url
        self.handler = handler
        self.protocol = None  # filled in by the factory in buildProtocol(...)
        self.is_open = False
        reactor.callInThread(self.handler.onWSInit, self)

    @crochet.wait_for(30)
    def send(self, message):
        if self.is_open:
            self.protocol.sendMessage(message.encode("utf-8"), False)
            return True
        return False

    @crochet.wait_for(30)
    def sendBinary(self, message):
        if self.is_open:
            self.protocol.sendMessage(message.data, True)
            return True
        return False

    @crochet.wait_for(30)
    def close(self):
        if self.is_open:
            self.protocol.sendClose()
            return True
        return False

    def _respond_closed(self):
        # Must be called via reactor.callInThread
        self.handler.onWSClosed(self)
        self.handler.onWSFinal(self)

    def _respond_error(self, error):
        # Must be called via reactor.callInThread
        self.handler.onWSError(self, error)
        self.handler.onWSFinal(self)


@crochet.wait_for(30)
def connect(url, handler):
    qws = _QuarkWebSocket(url, handler)
    try:
        factory = _QWSCFactory(qws, url)
    except Exception as exc:
        error = quark.WSError("Error connecting to URL <%s>: %s" % (url, exc))
        reactor.callInThread(qws._respond_error, error)
        return
    connectWS(factory)
