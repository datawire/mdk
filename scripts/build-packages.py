#!/usr/bin/env python

import os
import sys
from glob import glob
from subprocess import check_call


def build_python(package_dir):
    """Build Python package from the output of quark compile (output/py/mdk-2.0)."""
    check_call(["python", "setup.py", "bdist_wheel"], cwd=package_dir)
    package, = glob(os.path.join(package_dir, "dist/*.whl"))
    return package

def build_ruby(package_dir):
    """Build Ruby packages from the output of quark compile (output/rb/mdk-2.0)."""


def build_javascript(package_dir):
    """Build Javascript packages from the output of quark compile (output/js/mdk-2.0)."""


def build_java(package_dir):
    """Build Java packages from the output of quark compile (output/java/mdk-2.0)."""


def main(language, in_directory, out_directory):
    handlers = {"py": build_python,
                "rb": build_ruby,
                "js": build_javascript,
                "java": build_java}
    result = handlers[language](in_directory)
    for path in result:
        os.rename(path, os.path.join(out_directory, os.path.basename(path)))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])

