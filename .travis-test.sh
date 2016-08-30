#!/bin/bash
set -e

# Setup local Gem install instead of system install:
rvm use system
echo "install: --user-install" > ~/.gemrc
echo "gempath at $1 is $(gem env gempath)"
export PATH="$PATH":~/.quark/bin/:$(gem env gempath | tr : \\n | grep -F -e "$HOME/.gem/" | head -1)/bin

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
