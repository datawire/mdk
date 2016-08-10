quark 1.0;

package datawire_mdk_util 1.0.0;

use js bluebird 3.4.1;
include mdk_promises.js;

use actors.q;

import quark.os;
import quark.concurrent;
import actors.promise;

namespace mdk_util {
    @doc("A Supplier has a 'get' method that can return a value to anyone who needs it.")
    interface Supplier<T> {
    
        @doc("Gets a value")
        T get();
     
        /* BUG (compiler) -- Issue # --> https://github.com/datawire/quark/issues/143
           @doc("Gets a value or if null returns the given alternative.")
           T orElseGet(T alternative) 
           {
           T result = get();
           if (result != null) 
           {
           return result;
           }
           else
           {
           return alternative;
           }
           }
        */
    }

    @doc("EnvironmentVariable is a Supplier of Strings that come from the environment.")
    class EnvironmentVariable extends Supplier<String> {
        String variableName;

        EnvironmentVariable(String variableName) {
            self.variableName = variableName;
        }

        bool isDefined() {
            return get() != null;
        }

        String get() {
            return Environment.getEnvironment()[variableName];
        }

        // TODO: Remove once Issue #143 --> https://github.com/datawire/quark/issues/143 is resolved.
        String orElseGet(String alternative) {
            String result = get();
            if (result != null) {
                return result;
            }
            else {
                return alternative;
            }
        }
    }

    // This should be moved into Quark at some point:
    @doc("Utility to blockingly wait for a Promise to get a value.")
    class WaitForPromise {
        bool _finished(Object value, Condition done) {
            done.acquire();
            done.wakeup();
            done.release();
            return true;
        }

        static Object wait(Promise p, float timeout, String description) {
            Condition done = new Condition();
            WaitForPromise waiter = new WaitForPromise();
            p.andThen(bind(waiter, "_finished", [done]));

            // Wait until promise has result or we hit timeout:
            // XXX do we need to do while loop that's in FutureWait?
            long msTimeout = (timeout * 1000.0).round();
            done.acquire();
            done.waitWakeup(msTimeout);
            done.release();

            PromiseValue snapshot = p.value();
            if (!snapshot.hasValue()) {
                // XXX when we port this to Quark itself we should use a custom timeout
                // exception class.
                panic("Timeout waiting for " + description);
            }
            return snapshot.getValue();
        }
    }

    // This should be moved into quark at some point and cleaned up so it's less horrible:

    macro bool _isJavascript() $java{false} $py{False} $rb{false} $js{true};

    macro Object _jsresolve(Promise p) $js{require("../mdk_promises.js").quark_promise_to_bluebird($p)}
    $java{null}; // without this it won't compile

    Object toNativePromise(Promise p) {
        if (!_isJavascript()) {
            panic("This method only works on Javascript.");
        }
        return _jsresolve(p);
    }

    void extend(List<String> list, String value, int size) {
        while (list.size() < size) {
            list.add(value);
        }
    }

    bool versionMatch(String requested, String actual) {
        // null means unspecified
        if (requested == null) {
            return true;
        }

        List<String> reqparts = requested.split(".");
        List<String> actparts = actual.split(".");
        extend(reqparts, "0", 3);
        extend(actparts, "0", 3);

        // major must be equal
        if (reqparts[0] != actparts[0]) {
            return false;
        }

        // if minor is greater than we want that's ok
        if (actparts[1] > reqparts[1]) {
            return true;
        }

        // if minor is less than we want, that's not ok
        if (actparts[1] < reqparts[1]) {
            return false;
        }

        // when minor is equal, we check the bug fix
        return actparts[2] >= reqparts[2];
    }

}
