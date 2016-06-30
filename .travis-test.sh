#!/bin/bash
set -e
set -v
rvm use system
export GIT_BRANCH=`git rev-parse --abbrev-ref HEAD`
echo "Git branch is:" $GIT_BRANCH
for CODE_LANG in --python --ruby --java --javascript ; do
    echo "Language is:" $CODE_LANG
    bash install.sh $CODE_LANG $GIT_BRANCH
    ~/.quark/bin/quark install $CODE_LANG quark/mdk_test.q
    ~/.quark/bin/quark run $CODE_LANG quark/mdk_test.q
done
