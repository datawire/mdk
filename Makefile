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
	echo "* 'make clean' to undo setup and packages"

.PHONY: clean
clean:
	rm -fr virtualenv
	rm -fr virtualenv3
	rm -rf django110env
	rm -fr output
	rm -fr dist
	rm -f quark/*.qc
	rm -fr ~/.m2/repository/datawire_mdk
	rm -fr ~/.m2/repository/io/datawire/mdk
	rm -rf node_modules

virtualenv:
	virtualenv -p python2 virtualenv

.PHONY: python-dependencies
python-dependencies: virtualenv
	virtualenv/bin/pip install -r dev-requirements.txt

virtualenv3:
	virtualenv -p python3 virtualenv3

django110env:
	virtualenv -p python3 django110env

.PHONY: python3-dependencies
python3-dependencies: virtualenv3 django110env
	virtualenv3/bin/pip install -r dev-requirements.txt
	django110env/bin/pip install django\>=1.10

node_modules:
	mkdir node_modules

.PHONY: js-dependencies
js-dependencies: node_modules
	npm install express connect-timeout

.PHONY: setup
setup: python-dependencies python3-dependencies js-dependencies install-quark

.PHONY: install-quark
install-quark:
	which quark || \
		curl -# -L https://raw.githubusercontent.com/datawire/quark/master/install.sh | \
		bash -s -- -q `cat QUARK_VERSION.txt`

.PHONY: install-mdk
install-mdk: packages $(wildcard javascript/datawire_mdk_express/*)
	virtualenv/bin/pip install --upgrade dist/datawire_mdk-*-py2*-none-any.whl
	virtualenv3/bin/pip install --upgrade dist/datawire_mdk-*-*py3-none-any.whl
	django110env/bin/pip install --upgrade dist/datawire_mdk-*-*py3-none-any.whl
	gem install --no-doc dist/datawire_mdk-*.gem
	npm install output/js/mdk-2.0
	npm install javascript/datawire_mdk_express/
	cd output/java/mdk-2.0 && mvn install

.PHONY: test
test: install-mdk test-python test-python3

.PHONY: test-python
test-python:
	# Functional tests don't benefit from being run in another language, so
	# we only run them under Python 3:
	virtualenv/bin/py.test -n 4 -v unittests

.PHONY: test-python3
test-python3:
	virtualenv3/bin/py.test -n 4 -v unittests functionaltests

release-minor:
	virtualenv/bin/python scripts/release.py minor

release-patch:
	virtualenv/bin/python scripts/release.py patch

# Packaging commands:
output: $(wildcard quark/*.q) $(wildcard python/*.py) dist
	rm -rf output output.temp
	# Use installed Quark if we don't already have quark cli in PATH:
	which quark || source ~/.quark/config.sh; quark compile --include-stdlib -o output.temp quark/mdk-2.0.q
	cp python/*.py output.temp/py/mdk-2.0/mdk/
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
