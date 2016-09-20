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
    creds_existed = os.path.exists(creds)
    try:
        if not creds_existed:
            with open(creds, "w") as f:
                f.write(GEM_CONFIG.format(os.environ["RUBYGEMS_API_KEY"]))
            os.chmod(creds, 0o600)
        check_call(["gem", "push", gem])
    finally:
        if not creds_existed:
            # Delete the file we wrote:
            os.remove(creds)


def upload_npm():
    """
    Upload npm to npmjs repository.
    """
    mdk_npm = "output/js/mdk-2.0"
    express_npm = "javascript/datawire_mdk_express"
    config = os.path.expanduser("~/.npmrc")
    config_existed = os.path.exists(config)
    try:
        if not config_existed:
            with open(config, "w") as f:
                f.write(NPM_CONFIG.format(os.environ["NPM_API_KEY"]))
        check_call(["npm", "publish", mdk_npm])
        check_call(["npm", "publish", express_npm])
    finally:
        if not config_existed:
            # Delete the file we wrote:
            os.remove(config)

def upload_jar():
    """
    Upload jar to ossrh.
    """
    check_call("openssl aes-256-cbc -K $encrypted_530a0926551f_key -iv $encrypted_530a0926551f_iv -in ci/cikey.asc.enc -out ci/cikey.asc -d", shell=True)
    check_call("gpg --fast-import ci/cikey.asc", shell=True)
    check_call(["mvn", "-P", "release",
                "-f", "output/java/mdk-2.0",
                "--settings", "ci/mvnsettings.xml",
                "deploy", "nexus-staging:release:"])


def main():
    upload_jar()
    upload_python()
    upload_npm()
    upload_gem()


if __name__ == '__main__':
    main()
