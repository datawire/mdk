import mdk_utils;

class Panicker extends Callable {
    bool doit;

    Panicker(bool doit) {
        self.doit = doit;
    }

    void call() {
        if (doit) {
            panic("PANIC!");
        }
    }
}

class CallSafelyTest {
    void success() {
        Panicker p = new Panicker(false);
        Error result = callSafely(p);
        assertEqual(result, null);
    }

    void failure() {
        Panicker p = new Panicker(true);
        Error result = callSafely(p);
        assertEqual(false, result == null);
        assertEqual(true, result.message == "PANIC!");
    }
}

