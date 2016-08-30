"""
Ensure builds passed on Travis for current commit.

Because TravisPy is GPLv3 licensed this is a standalone program, the only
program that includes TravisPy in this repository and therefore only thing in
repository that is GPLv3 too.
"""

from subprocess import check_output
from travispy import TravisPy


def error(reason):
    """Exit with the given reason printed out."""
    exit("ERROR: " + reason)


def main():
    travis = TravisPy()
    revision = check_output(["git", "rev-parse", "HEAD"]).strip()
    build_passed = False
    for build in travis.builds(slug="datawire/mdk"):
        if build.commit.sha == revision + "1":
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


if __name__ == '__main__':
    main()
