/*
 * Copyright 2015 datawire. All rights reserved.
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

// Quark Runtime
/* jshint node: true */

// IMPORTANT: This is temporary and should be moved into Quark soon.

(function () {
    "use strict";

    var Promise = require("bluebird").getNewLibraryCopy();
    var clsBluebird = require('cls-bluebird');
    var cls = require("datawire_mdk/cls.js");

    clsBluebird( cls.namespace, Promise );

    function quark_promise_to_bluebird(quark_promise) {
        // Luckily we don't have to handle errors for now in MDK resolve(), but
        // we'll need to do so in Quark version.
        return new Promise(function (resolve, reject) {
            // Not necessary in Quark releases > 1.0.282, which can handle
            // undefined, but until then:
            function resolveWithoutUndefined(value) {
                resolve(value);
                return null;
            }
            quark_promise.andThen(resolveWithoutUndefined);
        });
    }

    exports.quark_promise_to_bluebird = quark_promise_to_bluebird;
})();

