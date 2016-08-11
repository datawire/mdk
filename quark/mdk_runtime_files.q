quark 1.0;

use actors.q;
import actors.core;

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

        FileContents(String path) {
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
}}
