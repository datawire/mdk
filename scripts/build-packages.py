#!/usr/bin/env python

import os
import sys
from json import loads, dumps
from glob import glob
from subprocess import check_call
from shutil import copyfile

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OVERRIDES = os.path.join(ROOT_DIR, "quark-overrides")


def build_python(package_dir):
    """Build Python package from the output of quark compile (output/py/mdk-2.0)."""
    copyfile(os.path.join(OVERRIDES, "setup.py"),
             os.path.join(package_dir, "setup.py"))
    copyfile(os.path.join(OVERRIDES, "README.rst"),
             os.path.join(package_dir, "README.rst"))
    python = os.path.join(ROOT_DIR, "virtualenv3/bin/python")
    assert os.path.exists(python), python
    check_call([python, "setup.py", "bdist_wheel", "--universal"], cwd=package_dir)
    return glob(os.path.join(package_dir, "dist/*.whl"))

def build_ruby(package_dir):
    """Build Ruby packages from the output of quark compile (output/rb/mdk-2.0)."""
    copyfile(os.path.join(OVERRIDES, "datawire_mdk.gemspec"),
             os.path.join(package_dir, "datawire_mdk.gemspec"))
    check_call(["gem", "build", "datawire_mdk.gemspec"], cwd=package_dir)
    return glob(os.path.join(package_dir, "*.gem"))


def build_javascript(package_dir):
    """Build Javascript packages from the output of quark compile (output/js/mdk-2.0)."""
    copyfile(os.path.join(OVERRIDES, "README.md"),
             os.path.join(package_dir, "README.md"))
    package_json_path = os.path.join(package_dir, "package.json")
    package_json = loads(os.path.join(OVERRIDES, "package.json.in"))
    generated_json = loads(file(package_json_path).read())
    package_json["dependencies"] = generated_json["dependencies"]
    with open(package_json_path, "w") as f:
        f.write(dumps(package_json))
    return []


def build_java(package_dir):
    """Build Java packages from the output of quark compile (output/java/mdk-2.0)."""
    copyfile(os.path.join(OVERRIDES, "pom.xml.manual"),
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

