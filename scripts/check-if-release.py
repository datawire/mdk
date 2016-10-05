#!/usr/bin/env python

"""
Check if the current commit is a release commit or not.

This is used by Jenkins to determine whether or not to trigger a build of
mdk-docs, which needs to be done on every new MDK release (but not on every
commit).
"""

from __future__ import print_function

from subprocess import check_output
from sys import exit

def main():
    diff = check_output(["git", "diff", "HEAD^", ".bumpversion.cfg"])
    if b"current_version = " in diff:
        print("Version changed in .bumpversion.cfg, that means this is a release.")
        exit(0)
    else:
        print("No changes to version in .bumpversion.cfg, this is not a release.")
        exit(1)

main()
