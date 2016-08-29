"""
Release the MDK.

The process:

0. Ensure current checkout is not dirty (i.e. everything is committed).
1. Ensure current commit has passing tests by talking to Travis API.
2. Bump versions on all relevant files.

(TODO: once we only have `master` branch and no more `develop` will add more
steps:

3. Git commit.
4. Tag with new version.
5. Tell user command to run to git push and actually release the code.)

For now however we will continue current process. I.e. local commit will need to
be pushed to branch on GitHub, that branch will be merged to `develop` with PR,
and `develop` merged to `master` with PR and then tag that release.

(TODO: There will also be infrastructure in the CI system to automatically upload
Python/Ruby/JS/Java packages on tagged commits.)


Usage:
  release.py patch
  release.py minor

Commands:
  patch      Bump the version's patch level, e.g. 1.0.0 -> 1.0.1
  minor      Bump the version's minor level, e.g. 1.0.2 -> 1.1.0
"""

HELP = __doc__

from subprocess import check_output
from docopt import docopt
from travispy import TravisPy


def error(reason):
    """Exit with the given reason printed out."""
    exit("ERROR: " + reason)


def ensure_not_dirty(options):
    """Ensure the current checkout has no uncomitted changes."""
    dirty = check_output(["git", "status", "--porcelain", "--untracked=no"]).splitlines()
    if dirty:
        error("git checkout has uncomitted changes.")


def ensure_passing_tests(options):
    """Talk to Travis CI, ensure all tests passed for the current git commit."""
    travis = TravisPy()
    revision = check_output(["git", "rev-parse", "HEAD"])
    build_passed = False
    for build in travis.builds(slug="datawire/mdk", number=50):
        if build.commit_id == revision:
            if build.passed:
                build_passed = True
                break
            else:
                error("Build either failed or is unfinished. Current state:"
                     + build.current_state())

    if not build_passed:
        error("No matching build found.")


def bump_versions(options):
    """Bump release version on all applicable files."""


def main():
    """Run the release."""
    options = docopt(HELP)
    for index, step in enumerate([ensure_not_dirty,
                                  ensure_passing_tests,
                                  bump_versions,]):
        print("Step {}: {}".format(index + 1, step.__name__))
        step(options)
    print("""\
All done! You can now push this branch to GitHub and get it merged to
`master` via `develop`.""")

if __name__ == '__main__':
    main()
