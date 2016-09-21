"""
Release the MDK.

The process:

1. Ensure current checkout is not dirty (i.e. everything is committed).
2. Ensure current branch is master.
3. Git pull so we're up-to-date with origin/master.
4. Ensure current commit has passing tests by talking to Travis API.
5. Bump versions on all relevant files using the bumpversion tool, then commit and tag.
6. Tell user command to run to git push and actually release the code.

Usage:
  release.py patch
  release.py minor

Commands:
  patch      Bump the version's patch level, e.g. 1.0.0 -> 1.0.1
  minor      Bump the version's minor level, e.g. 1.0.2 -> 1.1.0
"""

HELP = __doc__

import os
import sys
from subprocess import check_output, CalledProcessError, check_call
from docopt import docopt


def error(reason):
    """Exit with the given reason printed out."""
    exit("ERROR: " + reason)


def ensure_not_dirty(options):
    """Ensure the current checkout has no uncomitted changes."""
    dirty = check_output(["git", "status", "--porcelain", "--untracked=no"]).splitlines()
    if dirty:
        error("git checkout has uncomitted changes.")

def ensure_master(options):
    """Ensure the current branch is master."""
    branch = check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"]).strip()
    if branch != "master":
        error("Current checked out branch is %s. Please run:\n\n    git checkout master\n" % (branch,))


def git_pull(options):
    """Make sure master branch is up-to-date."""
    check_call(["git", "pull"])


def ensure_passing_tests(options):
    """Talk to Travis CI, ensure all tests passed for the current git commit."""
    try:
        check_output([sys.executable, "scripts/check-travis.py"])
    except CalledProcessError:
        # check-travis.py will print reason
        raise SystemExit(1)


def _bump_versions(options, config_path):
    """Bump release version, using specific config."""
    if options["patch"]:
        increment = "patch"
    elif options["minor"]:
        increment = "minor"
    check_output(["bumpversion",
                  "--verbose",
                  # List the changed files
                  "--list",
                  # Which config file to use
                  "--config-file", config_path, increment],
                 cwd=os.path.dirname(config_path) or ".")


def bump_mdk_versions(options):
    """Bump MDK release version."""
    _bump_versions(options, ".bumpversion.cfg")


def main():
    """Run the release."""
    options = docopt(HELP)
    for index, step in enumerate([ensure_not_dirty,
                                  ensure_master,
                                  git_pull,
                                  ensure_passing_tests,
                                  bump_mdk_versions,
                                  ]):
        print("Step {}: {}".format(index + 1, step.__name__))
        step(options)
    print("""\
The release has been committed and tagged locally.

You can now push it upstream by running:

    git push origin master --tags
""")

if __name__ == '__main__':
    main()
