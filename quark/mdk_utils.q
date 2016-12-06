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

    Error callSafely(Callable c) for go {
        err := nil
        defer func() {
            if r := recover(); r != nil {
                err = $buildError(fmt.Errorf("%v", r))
            }
        }()
        c.call()
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
        catch Exception => e
            return $buildError(e.to_s)
        end
    }
}
