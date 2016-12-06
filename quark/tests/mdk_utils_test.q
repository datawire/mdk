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
        assertEqual(result, nil);
    }

    void failure() {
        Division d = new Division(2);
        Error result = callSafely(d);
        assertEqual(true,
                    (result.substring("zero") != -1) ||
                    (result.substring("zero") != -1));
    }
}

