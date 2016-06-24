quark 1.0;

import quark.concurrent;
import quark.reflect;

namespace mdk {
    class Serializable {
        static Serializable decode(String message) {
            JSONObject json = message.parseJSON();
            String type = json["type"];
            Class clazz = Class.get(type);
            Serializable obj = ?clazz.construct([]);
            fromJSON(clazz, obj, json);

            return obj;
        }

        String encode() {
            Class clazz = self.getClass();
            JSONObject json = toJSON(self, clazz);
            json["type"] = clazz.getName();
            return json.toString();
        }
    }

    class LamportClock extends Serializable {
        Lock _mutex = new Lock();
        List<int> clocks = [];

        // ew.
        static LamportClock decode(String message) {
            return ?Serializable.decode(message);
        }

        String key() {
            _mutex.acquire();

            List<String> tmp = [];

            int i = 0;

            while (i < self.clocks.size()) {
                tmp.add(self.clocks[i].toString());
                i = i + 1;
            }

            String str = ",".join(tmp);

            _mutex.release();

            return str;
        }

        // XXX Not automagically mapped to str() or the like, even though
        // something should be.
        String toString() {
            _mutex.acquire();

            String str = "<LamportClock " + self.key() + ">";

            _mutex.release();

            return str;
        }

        int enter() {
            _mutex.acquire();

            int current = -1;

            self.clocks.add(0);
            current = self.clocks.size();

            _mutex.release();

            return current;
        }

        int leave(int popTo) {
            _mutex.acquire();

            int current = -1;

            self.clocks = self.clocks.slice(0, popTo);
            current = self.clocks.size();

            _mutex.release();

            return current;
        }

        void tick() {
            _mutex.acquire();

            int current = self.clocks.size();

            if (current > 0) {
                self.clocks[current - 1] = self.clocks[current - 1] + 1;
            }

            _mutex.release();
        }
    }

    class SharedContext extends Serializable {
        @doc("""
            Every SharedContext is given an ID at the moment of its creation;
            this is its originId. Every operation started as a result of the
            thing that caused the SharedContext to be created must use the 
            same SharedContext, and its originId will _never_ _change_.
        """)
        String originId;

        @doc("""
            To track causality, we use a Lamport clock.
        """)
        LamportClock clock = new LamportClock();

        @doc("""
            We also provide a map of properties for later extension. Rememeber
            that these, too, will be shared across the whole system.
        """)
        Map<String, Object> properties = {};

        int _lastEntry = 0;

        SharedContext() {}

        static SharedContext withOrigin(String originId) {
            SharedContext newContext = new SharedContext();
            newContext.originId = originId;
            newContext._lastEntry = newContext.clock.enter();

            return newContext;
        }

        // XXX ew.
        static SharedContext decode(String message) {
            return ?Serializable.decode(message);
        }

        String key() {
            return self.originId + ":" + self.clock.key();
        }

        // XXX Not automagically mapped to str() or the like, even though
        // something should be.
        String toString() {
            return "<SharedContext " + self.key() + ">";
        }

        void tick() {
            self.clock.tick();
        }

        SharedContext enter() {
            // Duplicate this object...
            SharedContext newContext = SharedContext.decode(self.encode());

            // ...enter...
            newContext._lastEntry = newContext.clock.enter();

            // ...and return the new context.
            return newContext;
        }

        SharedContext leave(int popTo) {
            // Duplicate this object...
            SharedContext newContext = SharedContext.decode(self.encode());

            // ...leave...
            newContext._lastEntry = newContext.clock.leave(newContext._lastEntry);

            // ...and return the new context.
            return newContext;
        }
    }
}
