#!/bin/bash
set -e
set -v
rvm use system
export GIT_BRANCH=`git rev-parse --abbrev-ref HEAD`
for CODE_LANG in --python --ruby --java --javascript ; do
    curl -# -L https://raw.githubusercontent.com/datawire/mdk/$GIT_BRANCH/install.sh | bash -s -- $CODE_LANG $GIT_BRANCH
    ~/.quark/bin/quark install $CODE_LANG quark/mdk_test.q
    ~/.quark/bin/quark run $CODE_LANG quark/mdk_test.q
done
