.PHONY: default
default:
	echo "Run 'make test' to run tests."

virtualenv:
	virtualenv virtualenv

.PHONY: python-dependencies
python-dependencies: virtualenv
	virtualenv/bin/pip install -r dev-requirements.txt

.PHONY: setup
setup: python-dependencies

.PHONY: test
test:
	virtualenv/bin/python -m unittest discover -v
