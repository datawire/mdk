/*
 * Copyright 2016 datawire. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// MDK Runtime for Node
/* jshint node: true */

(function () {
    "use strict";

    var timers = require("timers");
    var process = require("process");

    var WebSocket = require("ws");

    var quark = require("quark").quark;


    exports.now = function now() {
        return Date.now() / 1000.0;
    };


    exports.schedule = function schedule(callable, delayInSeconds) {
        function doCall () {
            quark.callUnaryCallable(callable, null);
        }
        timers.setTimeout(doCall, delayInSeconds * 1000);
    };


    exports.env_get = function env_get(key) {
        var res = process.env[key];
        if (typeof res !== "undefined") {
            return res;
        }
        return null;
    };


    function QuarkWebSocket(url, handler) {
        var self = this;
        handler.onWSInit(this);
        this.url = url;
        this.isOpen = false;

        try {
            this.socket = new WebSocket(url);
        } catch (exc) {
            handler.onWSError(this, new quark.WSError(exc.toString()));
        }

        this.socket.on("open", function () {
            self.isOpen = true;
            handler.onWSConnected(self);
        });

        this.socket.on("message", function (message, flags) {
            if (flags.binary) {
                //handler.onWSBinary(self, new runtime.Buffer(message));
                return;  // FIXME: Silently throw away binary messages
            } else {
                handler.onWSMessage(self, message);
            }
        });

        this.socket.on("close", function (/* code, message */) {
            handler.onWSClosed(self);
            self.socket.terminate();
            handler.onWSFinal(self);
        });

        this.socket.on("error", function (error) {
            handler.onWSError(self, new quark.WSError(error.toString()));
            self.socket.terminate();
            handler.onWSFinal(self);
        });
    }

    QuarkWebSocket.prototype.send = function (message) {
        if (this.isOpen) {
            this.socket.send(message);
            return true;
        }
        return false;
    };

    QuarkWebSocket.prototype.sendBinary = function(message) {
        if (this.isOpen) {
            this.socket.send(message.data, {binary:true});
            return true;
        }
        return false;
    };

    QuarkWebSocket.prototype.close = function() {
        if (this.isOpen) {
            this.socket.close();
            return true;
        }
        return false;
    };


    exports.connect = function connect(url, handler) {
        return new QuarkWebSocket(url, handler);
    };

})();
