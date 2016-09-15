import os
import sys
from subprocess import check_call, check_output


CODE_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "source"))


def run_python(command, extra_args=(), output=False):
    """
    Run a Python program.

    Returns output if output=True, in which case stderr will cause error.
    """
    args = [sys.executable, os.path.join(CODE_PATH, command)] + list(extra_args)
    if output:
        command = check_output
    else:
        command = check_call
    return command(args)
