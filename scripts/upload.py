"""
Upload packages to PyPI, RubyGems, NPM and Maven.

We use temporary file to ensure passwords do not get leaked into Travis logs via
errors or tracebacks.
"""

import os
from glob import glob
from subprocess import check_call
from tempfile import NamedTemporaryFile


PYPI_CONFIG = """[distutils]
index-servers=pypi

[pypi]
repository = https://pypi.python.org/pypi
username = datawire
password = {}
"""

GEM_CONFIG = """\
---
:rubygems_api_key: {}
"""

NPM_CONFIG = "//registry.npmjs.org/:_authToken={}"


def upload_python():
    """
    Upload wheel to PyPI.
    """
    wheel, = glob("dist/datawire_mdk*.whl")
    with NamedTemporaryFile() as f:
        f.write(PYPI_CONFIG.format(os.environ["PYPI_PASSWORD"]))
        f.flush()
        check_call(["twine", "upload", "--config-file", f.name, wheel])


def upload_gem():
    """
    Upload gem to rubygems.org.
    """
    gem, = glob("dist/datawire_mdk*.gem")
    directory = os.path.expanduser("~/.gem")
    if not os.path.exists(directory):
        os.makedirs(directory)
    creds = os.path.join(directory, "credentials")
    creds_existed = os.path.exist(creds)
    try:
        if not creds_existed:
            with open(creds, "w") as f:
                f.write(GEM_CONFIG.format(os.environ["RUBYGEMS_API_KEY"]))
        check_call(["gem", "push", gem])
    finally:
        if not creds_existed:
            # Delete the file we wrote:
            os.remove(creds)


def upload_npm():
    """
    Upload npm to npmjs repository.
    """
    npm = os.path.join("output/js/mdk-2.0")
    config = os.path.expanduser("~/.npmrc")
    config_existed = os.path.exists(config)
    try:
        if not config_existed:
            with open(config, "w") as f:
                f.write(NPM_CONFIG.format(os.environ["NPM_API_KEY"]))
        check_call(["npm", "publish", npm])
    finally:
        if not config_existed:
            # Delete the file we wrote:
            os.remove(config)


def main():
    upload_python()
    upload_npm()
    upload_gem()


if __name__ == '__main__':
    main()
