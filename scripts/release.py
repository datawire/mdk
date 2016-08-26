"""
Release the MDK.

The process:

1. Ensure current commit has passing tests by talking to Github API.
2. Bump versions on all relevant files.

Later, once we only have `master` branch and no more `develop` will add more
steps:

3. Git commit.
4. Tag with new version.
5. Tell user command to run to git push and actually release the code.

For now however we will continue current process. I.e. local commit will need to
be pushed to branch on GitHub, that branch will be merged to `develop` with PR,
and `develop` merged to `master` with PR and then tag that release.

There will also be infrastructure in the CI system to automatically upload
Python/Ruby/JS/Java packages on tagged commits.


Usage:
  release.py patch
  release.py minor

Commands:
  patch      Bump the version's patch level, e.g. 1.0.0 -> 1.0.1
  minor      Bump the version's minor level, e.g. 1.0.2 -> 1.1.0
"""

HELP = __doc__


from docopt import docopt


def ensure_passing_tests(options):
    """Talk to GitHub, ensure all tests passed for the current git commit."""


def bump_versions(options):
    """Bump release version on all applicable files."""


def main():
    """Run the release."""
    options = docopt(HELP)
    for index, step in enumerate([ensure_passing_tests,
                                  bump_versions,
                                  ]):
        print("Step {}: {}".format(index + 1, step.__name__))
        step(options)
    print("""\
All done! You can now push this branch to GitHub and get it merged to
`master` via `develop`.""")

if __name__ == '__main__':
    main()
