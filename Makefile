SHELL=/bin/bash

.PHONY: default
default:
	echo "You can run:"
	echo "* 'make setup' to setup the environment"
	echo "* 'make test' to run tests (requires setup)"
	echo "* 'make packages' to build packages"
	echo "* 'make release' to do a release"

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
	source virtualenv/bin/activate && python -m unittest discover -v

release:
	virtualenv/bin/python scripts/release.py

# Packaging commands:
output: $(wildcard quark/*.q) dist
	rm -rf output
	# TODO: Once we have new Quark release, add --include-stdlib option:
	quark compile -o output.temp quark/mdk-2.0.q
	mv output.temp output

dist:
	mkdir dist

.PHONY: packages
packages: python-packages ruby-packages javascript-packages java-packages

.PHONY: python-packages
python-packages: output
	python scripts/build-packages.py py output/py/mdk-2.0 dist/

.PHONY: ruby-packages
ruby-packages: output
	python scripts/build-packages.py rb output/rb/mdk-2.0 dist/

.PHONY: javascript-packages
javascript-packages: output
	python scripts/build-packages.py js output/js/mdk-2.0 dist/

.PHONY: java-packages
java-packages: output
	python scripts/build-packages.py java output/java/mdk-2.0 dist/
