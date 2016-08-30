#!/bin/bash
set -e

# Make sure we're using correct version of Ruby:
rvm use --ruby-version 2.3

# Display what ruby we're using, to make sure it's correct:
ruby --version
gem --version

# Prepare virtualenv:
make setup

# Enter the virtualenv:
source virtualenv/bin/activate

echo "Git commit is:" $TRAVIS_COMMIT
for CODE_LANG in --python --ruby --java --javascript ; do
    echo "Language is:" $CODE_LANG
    bash install.sh $CODE_LANG $TRAVIS_COMMIT
done

# Run the tests:
make test
