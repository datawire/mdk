import os
import tempfile

"""
TODO: This is all semi-broken since in Python quark.String is not Unicode
all the time.
"""

__all__ = ["_mdk_mktempdir", "_mdk_writefile", "_mdk_deletefile",
           "_mdk_file_contents", "_mdk_readfile"]

def _mdk_mktempdir():
    """Create temporary directory."""
    return tempfile.mkdtemp()

def _mdk_writefile(path, contents):
    """Write a file to disk."""
    with open(path, "wb") as f:
        f.write(contents.encode("utf-8"))

def _mdk_readfile(path):
    """Read a file's contents."""
    with open(path, "rb") as f:
        return f.read().decode("utf-8")

def _mdk_deletefile(path):
    """Delete a file."""
    os.remove(path)

def _mdk_file_contents(path):
    """List contents of directory, or just the file if it's a file."""
    if os.path.isdir(path):
        return [os.path.join(path, name) for name in os.listdir(path)]
    else:
        return [path]
