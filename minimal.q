quark *;

namespace mdk {
    api.MDK init() {
        return api.GetMDK();
    }
    api.MDK start() {
        api.MDK m = init();
        m.start();
        return m;
    }
    namespace api {
        interface Session {
            String externalize()
                void log(String msg);
        }

        interface Plugin {
            void init(MDK mdk);
            void onSession(Session session);
        }

        interface MDK {
            void start();
            Session session();
            Session join(String id);
            void stop();

            void register(Plugin plugin);
        }

        MDK GetMDK() {
            return impl.MDK();
        }
    }

    namespace impl {
        class MDK extends api.MDK {
            Plugin plugin;
            void start() {}
            api.Session session() {
                return self._session(helpers.uuid());
            }
            api.Session join(String id) {
                return self._session(id);
            }
            api.Session _session(String id) {
                Session s = new Session(self, id);
                if (plugin != null) {
                    plugin.onSession(s);
                }
                return s;
            }
            void stop() {}
            void register(Plugin plugin) {
                plugin.init(self);
            }
        }

        class Session extends api.Session {
            Session(MDK mdk, String id) {
            }
            void log(String msg) { print(msg);
            }

            String externalize() { return "id";
            }
        }
    }

    namespace helpers {
        String uuid() { return "u-u-i-d"; }
    }
}
