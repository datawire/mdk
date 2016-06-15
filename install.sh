#!/bin/bash

set -e

PYVER=$(python -c "import platform ; print(platform.python_version())" 2>/dev/null)

if [ -z "$PYVER" ]; then
  # No python. That's a problem.
  cat <<EOF >&2
You don't seem to have Python installed! Check out https://www.python.org to
get that sorted out.
EOF
  exit 1
fi

if [ $(echo "$PYVER" | egrep -c '^2\.') -eq 0 ]; then
  # We need python 2.
  cat <<"EOF" >&2
You seem to have Python $PYVER installed. We only support Python 2, and we need 2.7
or higher. Check out https://www.python.org to get that sorted out.
EOF
  exit 1
fi

if ! command -v pip >/dev/null 2>&1; then
  # No pip. That's a problem.
  cat <<EOF >&2
You don't seem to have pip installed. The easiest way to fix this may be
to install and use virtualenv -- check out https://virtualenv.pypa.io/en/stable for
more!
EOF
  exit 1
fi

if ! command -v quark >/dev/null 2>&1; then
  if [ ! -f $HOME/.quark/config.sh ]; then
    # No quark. Install it.
    echo "== Installing Quark!"

    curl -# -L https://raw.githubusercontent.com/datawire/quark/master/install.sh | bash -s -- rel/0.7.6
  fi

  . $HOME/.quark/config.sh
fi

# Compile quark packages.
echo "== Compiling the MDK"
quark install --python https://raw.githubusercontent.com/datawire/discovery/dev/2.0/quark/{discovery-2.0.0,datawire_introspection}.q

# Get Python set up.
echo "== Verifying Flask"
pip install requests flask

# All done.
echo "== All done"
