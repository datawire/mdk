#!/bin/bash
set -e

# Remove this when bug is fixed:
export DATAWIRE_TOKEN=""

# Setup local Gem install instead of system install:
rvm use system
echo "install: --user-install" > ~/.gemrc
echo "gempath at $1 is $(gem env gempath)"
export PATH="$PATH":$(gem env gempath | tr : \\n | grep -F -e "$HOME/.gem/" | head -1)/bin

echo "Git commit is:" $TRAVIS_COMMIT
for CODE_LANG in --python --ruby --java --javascript ; do
    echo "Language is:" $CODE_LANG
    bash install.sh $CODE_LANG $TRAVIS_COMMIT
    ~/.quark/bin/quark install $CODE_LANG quark/mdk_test.q
    ~/.quark/bin/quark run $CODE_LANG quark/mdk_test.q
done
