namespace mdk_utils {
    /* An object that can be called with no arguments. */
    interface Callable {
        void call();
    }

    /* Base class for errors. */
    class Error {
        String message;

        Error(String message) {
            self.message = message;
        }
    }

    Error buildError(String message) {
        return new Error(message);
    }

    /* Throw an exception. */
    void panic(String message);

    void panic(String message) for go {
        panic($message)
    }

    void panic(String message) for java {
        throw new RuntimeException($message);
    }

    void panic(String message) for ruby {
        raise $message
    }

    void panic(String message) for python {
        raise Exception($message);
    }

    void panic(String message) for javascript {
        throw new Error(message);
    }

    /* Call a Callable, catching native exceptions.

    Returns an Error on error, null on failure.
    */
    Error callSafely(Callable c);

    Error callSafely(Callable c) for java {
        try {
            c.call();
            return null;
        } catch (Exception e) {
            return $buildError(e.toString());
        }
    }

    Error callSafely(Callable c) for go import "fmt" {
        // Workaround for lack of ability to reference Error class:
        err := $buildError("");
        err = nil;
        defer func() {
            if r := recover(); r != nil {
                err = $buildError(fmt.Sprintf("%v", r))
            }
        }()
        c.Call()
        return err
    }

    Error callSafely(Callable c) for python {
        try:
            c.call()
        except Exception as e:
            return $buildError(str(e))
    }

    Error callSafely(Callable c) for javascript {
        try {
            c.call();
            return null;
        } catch (e) {
            return $buildError(e.toString());
        }
    }

    Error callSafely(Callable c) for ruby {
        begin
            c.call()
            return nil
        rescue Exception => e
            return $buildError("#{e.class.to_s}: #{e.to_s}")
        end
    }
}
