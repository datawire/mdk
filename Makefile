SHELL=/bin/bash

.PHONY: default
default:
	echo "Run 'make setup' to setup the environment, 'make test' to run tests."

virtualenv:
	virtualenv virtualenv

.PHONY: python-dependencies
python-dependencies: virtualenv
	virtualenv/bin/pip install -r dev-requirements.txt

.PHONY: setup
setup: python-dependencies

.PHONY: test
test:
	# For now we rely on either .travis-test.sh or the user to install the
	# MDK. This means tests.test_endtoend will fail if you are not on Travis
	# or have not installed the MDK.
	virtualenv/bin/python -m unittest discover -v
