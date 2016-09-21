quark *;

namespace mdk {
    namespace api {
        interface Session {
            String externalize()
                void log(String msg);
        }

        interface MDK {
            void start();
            Session session();
            Session join(String id);
            void stop();
        }

        MDK GetMDK() {
            return impl.MDK();
        }
    }

    namespace impl {
        class MDK extends api.MDK {
            void start() {}
            api.Session session() {
                return new Session(self, helpers.uuid());
            }
            api.Session join(String id) {
                return new Session(self, id);
            }
            void stop() {}
        }

        class Session extends api.Session {
            Session(MDK mdk, String id) {
            }
            void join(String id) {
            }

            String externalize() { return "id";
            }
        }
    }

    namespace helpers {
        String uuid() { return "u-u-i-d"; }
    }
}
