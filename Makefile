SHELL=/bin/bash

.PHONY: default
default:
	echo "You can run:"
	echo "* 'make setup' to setup the environment"
	echo "* 'make test' to run tests (requires setup)"
	echo "* 'make packages' to build packages (.whl, .gem, etc.)"
	echo "* 'make release-patch' to do a patch release (2.0.x)"
	echo "* 'make release-minor' to do a minor release (2.x.0)"
	echo "* 'make upload-packages' to upload packages to native repos (e.g. .whl to PyPI, .gem to RubyGems.org, etc.)"

virtualenv:
	virtualenv -p python2 virtualenv

.PHONY: python-dependencies
python-dependencies: virtualenv
	virtualenv/bin/pip install -r dev-requirements.txt

virtualenv3:
	virtualenv -p python3 virtualenv3

.PHONY: python3-dependencies
python3-dependencies: virtualenv3
	virtualenv3/bin/pip install -r dev-requirements.txt

.PHONY: setup
setup: python-dependencies python3-dependencies install-quark

.PHONY: install-mdk
install-mdk: packages
	virtualenv/bin/pip install dist/

.PHONY: test
test:
	# For now we rely on either .travis-test.sh or the user to install the
	# MDK. This means tests will fail if you are not on Travis
	# or have not installed the MDK.
	source virtualenv/bin/activate && py.test -n 4 -v tests
	source virtualenv3/bin/activate && py.test -n 4 -v tests

release-minor:
	source virtualenv/bin/activate; python scripts/release.py minor

release-patch:
	source virtualenv/bin/activate; python scripts/release.py patch

# Packaging commands:
output: $(wildcard quark/*.q) dist
	rm -rf output
	# Use installed Quark if we don't already have quark cli in PATH:
	which quark || source ~/.quark/config.sh; quark compile --include-stdlib -o output.temp quark/mdk-2.0.q
	cp -R output.temp/py output.temp/py3
	futurize -nw --no-diffs --unicode-literals --both-stages  output.temp/py3/mdk-2.0
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


# Package upload commands
.PHONY: upload-packages
upload-packages: packages
	source virtualenv/bin/activate; python scripts/upload.py
