import mdk_utils;

class Division extends Callable {
    int divisor;
    int result;

    Division(int d) {
        self.divisor = d;
    }

    void call() {
        self.result = 10 / self.divisor;
    }
}

class CallSafelyTest {
    void success() {
        Division d = new Division(2);
        Error result = callSafely(d);
        assertEqual(d.result, 5);
        assertEqual(result, null);
    }

    void failure() {
        Division d = new Division(2);
        Error result = callSafely(d);
        assertEqual(true, result.message.contains("zero") ||
                          result.message.contains("zero"));
    }
}

