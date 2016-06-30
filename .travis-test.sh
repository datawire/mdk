#!/bin/bash
# BEGONE, rvm!
PATH=$(echo "$PATH" | tr : \\n |
              grep -vF -e /.local/ -e /.rvm/ -e /.gem/ |
              tr \\n : | sed -e's/:$//' )
rm -fr ~/.rvm
rm -fr ~/.local
unset $(env | grep -Fe ~/.rvm | cut -d= -f1)
echo "install: --user-install" > ~/.gemrc
echo "gempath at $1 is $(gem env gempath)"
PATH="$PATH":$(gem env gempath | tr : \\n | grep -F -e "$HOME/.gem/" | head -1)/bin

export GIT_BRANCH=`git rev-parse --abbrev-ref HEAD`
for CODE_LANG in --python --ruby --java --javascript ; do
    curl -# -L https://raw.githubusercontent.com/datawire/mdk/$GIT_BRANCH/install.sh | bash -s -- $CODE_LANG $GIT_BRANCH
    ~/.quark/bin/quark install $CODE_LANG quark/mdk_test.q
    ~/.quark/bin/quark run $CODE_LANG quark/mdk_test.q
done
