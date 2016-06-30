#!/bin/bash
set -e
rvm use system
echo "Git commit is:" $TRAVIS_COMMIT
for CODE_LANG in --python --ruby --java --javascript ; do
    echo "Language is:" $CODE_LANG
    bash install.sh $CODE_LANG $TRAVIS_COMMIT
    ~/.quark/bin/quark install $CODE_LANG quark/mdk_test.q
    ~/.quark/bin/quark run $CODE_LANG quark/mdk_test.q
done
