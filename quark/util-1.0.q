quark 1.0;

package datawire_mdk_util 2.0.32;

use js bluebird 3.4.1;
include mdk_promises.js;

include mdk_runtime.q;

import quark.os;
import quark.concurrent;
import mdk_runtime.promise;

namespace mdk_util {
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
            PromiseValue snapshot = p.value();
            if (snapshot.hasValue()) {
                return snapshot.getValue();
            }

            Condition done = new Condition();
            WaitForPromise waiter = new WaitForPromise();
            p.andThen(bind(waiter, "_finished", [done]));

            // Wait until promise has result or we hit timeout:
            // XXX do we need to do while loop that's in FutureWait?
            long msTimeout = (timeout * 1000.0).round();
            done.acquire();
            done.waitWakeup(msTimeout);
            done.release();

            snapshot = p.value();
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
        extend(reqparts, "0", 2);
        extend(actparts, "0", 2);

        int reqmajor = reqparts[0].parseInt().getValue();
        int actmajor = actparts[0].parseInt().getValue();
        int reqminor = reqparts[1].parseInt().getValue();
        int actminor = actparts[1].parseInt().getValue();

        // major must be equal since it's complete incompatibility
        if (reqmajor != actmajor) {
            return false;
        }

        // minor implies backwards compatibility
        if (actminor >= reqminor) {
            return true;
        }

        return false;
    }

}
