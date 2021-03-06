quark 1.0;

include mdk_runtime_files.py;

import mdk_runtime;
import mdk_runtime.actors;

namespace mdk_runtime {
namespace files {
    @doc("""
    Message to FileActor asking to be notified of files' changing contents and
    deletions for the given directory or file path.
    """)
    class SubscribeChanges {
        String path;

        SubscribeChanges(String path) {
            self.path = path;
        }
    }

    @doc("Message from FileActor with contents of a file.")
    class FileContents {
        String path;
        String contents;

        FileContents(String path, String contents) {
            self.path = path;
            self.contents = contents;
        }
    }

    @doc("Message from FileActor indicating a file was deleted.")
    class FileDeleted {
        String path;

        FileDeleted(String path) {
            self.path = path;
        }
    }

    @doc("""
    File interactions.

    Accepts:
    - SubscribeChanges messages, which result in FileContents and FiledDeleted
      messages being sent to original subscriber.
    """)
    class FileActor extends Actor {
        // These should really all be messages, since production-grade
        // implementations will want to do all I/O interaction in another thread
        // to keep MDK event loop from blocking. And so we want to use messages
        // to indicate asynchronicity. We can fix that another day, though,
        // especially since initial use case is just testing.
        @doc("Create a temporary directory and return its path.")
        String mktempdir();

        @doc("Write a file with UTF-8 encoded text.")
        void write(String path, String contents);

        @doc("Delete a file.")
        void delete(String path);
    }

    macro void _write(String path, String contents)
        $py{__import__("mdk_runtime_files")._mdk_writefile($path, $contents)}
        $java{do {} while (false);}
        $js{false}
        $rb{false};

    macro void _delete(String path)
        $py{__import__("mdk_runtime_files")._mdk_deletefile($path)}
        $java{do {} while (false);}
        $rb{false}
        $js{false};

    macro String _mktempdir() $py{__import__("mdk_runtime_files")._mdk_mktempdir()} $js{""} $java{""} $rb{""};

    @doc("""
    Polling-based subscriptions.

    Should switch to inotify later on.

    Shim over native implementations. Need better way to do this.
    """)
    class FileActorImpl extends FileActor {
        Actor scheduling;
        MessageDispatcher dispatcher;
        List<_Subscription> subscriptions = [];
        bool stopped = false;

        FileActorImpl(MDKRuntime runtime) {
            self.scheduling = runtime.getScheduleService();
        }

        String mktempdir() {
            return _mktempdir();
        }

        void write(String path, String contents) {
            _write(path, contents);
        }

        void delete(String path) {
            _delete(path);
        }

        void _checkSubscriptions() {
            if (self.stopped) {
                return;
            }
            self.dispatcher.tell(self, new Schedule("poll", 1.0), self.scheduling);
            int idx = 0;
            while (idx < self.subscriptions.size()) {
                self.subscriptions[idx].poll();
                idx = idx + 1;
            }
        }

        void onStart(MessageDispatcher dispatcher) {
            self.dispatcher = dispatcher;
            self._checkSubscriptions();
        }

        void onStop() {
            self.stopped = true;
        }

        void onMessage(Actor origin, Object message) {
            String typeId = message.getClass().id;
            if (typeId == "mdk_runtime.Happening") {
                self._checkSubscriptions();
                return;
            }
            if  (typeId == "mdk_runtime.files.SubscribeChanges") {
                SubscribeChanges subscribe = ?message;
                self.subscriptions.add(new _Subscription(self, origin, subscribe.path));
                return;
            }
        }

        void _send(Object message, Actor destination) {
            self.dispatcher.tell(self, message, destination);
        }
    }

    @doc("A specific file notification subscription.")
    class _Subscription {
        String path;
        FileActorImpl actor;
        Actor subscriber;
        List<String> previous_listing = [];

        _Subscription(FileActorImpl actor, Actor subscriber, String path) {
            self.subscriber = subscriber;
            self.actor = actor;
            self.path = path;
        }

        // Should return just the file path if it's a file, the contents if it's
        // a directory.
        macro List<String> contents(String path) $py{__import__("mdk_runtime_files")._mdk_file_contents($path)}
                                                 $java{null} $js{null} $rb{[]};

        macro String read(String path) $py{__import__("mdk_runtime_files")._mdk_readfile($path)}
                                       $java{null} $js{null} $rb{""};

        void poll() {
            List<String> new_listing = self.contents(self.path);
            // Anything that exists we read the contents, as if it's changed:
            int idx = 0;
            while (idx < new_listing.size()) {
                self.actor._send(new FileContents(new_listing[idx],
                                                  self.read(new_listing[idx])),
                                 self.subscriber);
                idx = idx + 1;
            }
            // Anything that is missing from new listing compared to old one we
            // send a dlelete notification:
            idx = 0;
            int jdx;
            bool found;
            while (idx < previous_listing.size()) {
                jdx = 0;
                found = false;
                while (jdx < new_listing.size()) {
                    if (previous_listing[idx] == new_listing[jdx]) {
                        found = true;
                        break;
                    }
                    jdx = jdx + 1;
                }
                if (!found) {
                    self.actor._send(new FileDeleted(previous_listing[idx]),
                                     self.subscriber);
                }
                idx = idx + 1;
            }
            self.previous_listing = new_listing;
        }
    }
}}
