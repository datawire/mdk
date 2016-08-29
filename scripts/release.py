"""
Release the MDK.

The process:

0. Ensure current checkout is not dirty (i.e. everything is committed).
1. Ensure current commit has passing tests by talking to Travis API.
2. Bump versions on all relevant files using the bumpversion tool.

(TODO: once we only have `master` branch and no more `develop` will add more
steps:

3. Git commit. Can be done via bumpversion.
4. Tag with new version. Can be done via bumpversion.
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
    revision = check_output(["git", "rev-parse", "HEAD"]).strip()
    build_passed = False
    for build in travis.builds(slug="datawire/mdk"):
        if build.commit.sha == revision:
            if build.passed:
                build_passed = True
                break
            else:
                error("Found the build but it has not passed.\n    Build state: "
                      + build.state +
                      "\n    Build URL: https://travis-ci.org/datawire/mdk/builds/"
                      + str(build.id))

    if not build_passed:
        error("No matching build found on Travis CI.")


def bump_versions(options):
    """Bump release version on all applicable files."""
    if options["patch"]:
        increment = "patch"
    elif options["minor"]:
        increment = "minor"
    check_output(["bumpversion", "--verbose", "--list", increment])


def main():
    """Run the release."""
    options = docopt(HELP)
    for index, step in enumerate([]):#ensure_not_dirty,
                                  #ensure_passing_tests,
                                  #bump_versions,]):
        print("Step {}: {}".format(index + 1, step.__name__))
        step(options)
    print("""\
Version numbers have been incremented. You should now:

1. Inspect the changes in the branch.
2. git add all changed files.
3. git commit.
4. git push to GitHub.
5. Open a PR into `develop`.
5. Merge PR into `develop` when tests pass.
6. Merge `develop` into `master`.
7. Create a release using the GitHub UI.

These steps will be automated in future iterations of the release automation.
""")

if __name__ == '__main__':
    main()
