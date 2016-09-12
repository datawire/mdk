#!/bin/bash
set -e

# Make sure we're using correct version of Ruby:
rvm use --ruby-version 2.3

# Display what ruby we're using, to make sure it's correct:
ruby --version
gem --version

# Prepare virtualenv:
make setup

# Run the tests:
make test
