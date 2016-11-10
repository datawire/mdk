import os
from subprocess import check_call, check_output


CODE_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "source"))
ROOT_PATH = os.path.abspath(os.path.join(CODE_PATH, "../.."))


def run_python(python_binary, command, extra_args=(), output=False,
               additional_env={}):
    """
    Run a Python program.

    Returns output if output=True, in which case stderr will cause error.
    """
    args = [python_binary, os.path.join(CODE_PATH, command)] + list(extra_args)
    if output:
        command = check_output
    else:
        command = check_call
    env = os.environ.copy()
    env.update(additional_env)
    return command(args, env=env)
