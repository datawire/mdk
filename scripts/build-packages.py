#!/usr/bin/env python

import os
import sys
from glob import glob
from subprocess import check_call
from shutil import copyfile

ROOT_DIR=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def build_python(package_dir):
    """Build Python package from the output of quark compile (output/py/mdk-2.0)."""
    python = os.path.join(ROOT_DIR, "virtualenv/bin/python2")
    assert os.path.exists(python), python
    print(python)
    check_call([python, "setup.py", "bdist_wheel", "--universal"], cwd=package_dir)
    return glob(os.path.join(package_dir, "dist/*.whl"))

def build_ruby(package_dir):
    """Build Ruby packages from the output of quark compile (output/rb/mdk-2.0)."""
    check_call(["gem", "build", "datawire_mdk.gemspec"], cwd=package_dir)
    return glob(os.path.join(package_dir, "*.gem"))


def build_javascript(package_dir):
    """Build Javascript packages from the output of quark compile (output/js/mdk-2.0)."""
    # We just upload straight from directory, I believe
    return []


def build_java(package_dir):
    """Build Java packages from the output of quark compile (output/java/mdk-2.0)."""
    copyfile(os.path.join(ROOT_DIR, "pom.xml.manual"),
             os.path.join(package_dir, "pom.xml"))
    return []


def main(language, in_directory, out_directory):
    handlers = {"py": build_python,
                "rb": build_ruby,
                "js": build_javascript,
                "java": build_java}
    results = handlers[language](in_directory)
    for result in results:
        target = os.path.join(out_directory, os.path.basename(result))
        print("Moving %s to %s" % (result, target))
        os.rename(result, target)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])

