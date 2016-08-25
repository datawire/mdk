#!/usr/bin/env python

import os
import sys
from glob import glob
from subprocess import check_call


def build_python(directory):
    """Build Python packages from the output of quark compile (output/py)."""
    result = []
    for package_name in os.listdir(directory):
        package_dir = os.path.join(directory, package_name)
        check_call(["python", "setup.py", "bdist_wheel"], cwd=package_dir)
        result.extend(glob(os.path.join(package_dir, "dist/*.whl")))
    return result

def build_ruby(directory):
    """Build Ruby packages from the output of quark compile (output/rb)."""


def build_javascript(directory):
    """Build Javascript packages from the output of quark compile (output/js)."""


def build_java(directory):
    """Build Java packages from the output of quark compile (output/java)."""


def main(language, in_directory, out_directory):
    handlers = {"py": build_python,
                "rb": build_ruby,
                "js": build_javascript,
                "java": build_java}
    result = handlers[language](os.path.join(in_directory, language))
    for path in result:
        os.rename(path, os.path.join(out_directory, os.path.basename(path)))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])

