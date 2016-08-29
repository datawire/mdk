"""
Upload packages to PyPI, RubyGems, NPM and Maven.
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


def upload_python():
    """
    Upload wheel to PyPI.

    We use temporary file to ensure PyPI password does not get leaked into
    Travis logs via errors or tracebacks.
    """
    wheel, = glob("dist/datawire_mdk*.whl")
    with NamedTemporaryFile() as f:
        f.write(PYPI_CONFIG.format(os.environ["PYPI_PASSWORD"]))
        f.flush()
        check_call(["twine", "upload", "--config-file", f.name, wheel])


def main():
    upload_python()


if __name__ == '__main__':
    main()
