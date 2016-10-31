SHELL=/bin/bash

.PHONY: default
default:
	@echo "You can run:"
	@echo "* 'make setup' to setup the environment"
	@echo "* '[sudo] make setup-docker' to prepare docker images for tests"
	@echo "* 'make test' to run tests (requires setup, setup-docker, and DATAWIRE_TOKEN)"
	@echo "* 'make packages' to build packages (.whl, .gem, etc.)"
	@echo "* 'make release-patch' to do a patch release (2.0.x)"
	@echo "* 'make release-minor' to do a minor release (2.x.0)"
	@echo "* 'make upload-packages' to upload packages to native repos (e.g. .whl to PyPI, .gem to RubyGems.org, etc.)"
	@echo "* 'make clean' to undo setup and packages"

.PHONY: clean
clean:
	rm -fr virtualenv
	rm -fr virtualenv3
	rm -rf django110env
	rm -fr output
	rm -fr dist/?*.*
	rm -f quark/*.qc quark/tests/*.qc
	rm -fr ~/.m2/repository/datawire_mdk
	rm -fr ~/.m2/repository/io/datawire/mdk
	rm -rf node_modules
	find . -name "__pycache__" -print0 | xargs -0 rm -fr
	-docker kill websocket-echo
	docker rmi datawire/websocket-echo:latest
	docker rmi datawire/websocket-echo:`node -e "console.log(require('./docker/websocket-echo/package.json').version)"`
	docker rmi datawire/mdk-quark-run:latest
	docker rmi datawire/mdk-quark-run:`sed s/v//g < QUARK_VERSION.txt`

virtualenv: virtualenv/bin/pip

virtualenv/bin/pip:
	rm -rf virtualenv
	virtualenv -p python2 virtualenv
	virtualenv/bin/pip install -U pip

.PHONY: python-dependencies
python-dependencies: virtualenv
	virtualenv/bin/pip install -r dev-requirements.txt

virtualenv3: virtualenv3/bin/pip

virtualenv3/bin/pip:
	rm -rf virtualenv3
	virtualenv -p python3 virtualenv3
	virtualenv3/bin/pip install -U pip

django110env: django110env/bin/pip

django110env/bin/pip:
	rm -rf django110env
	virtualenv -p python3 django110env
	django110env/bin/pip install -U pip

.PHONY: python3-dependencies
python3-dependencies: virtualenv3 django110env
	virtualenv3/bin/pip install -r dev-requirements.txt
	django110env/bin/pip install django\>=1.10

node_modules:
	mkdir node_modules

.PHONY: js-dependencies
js-dependencies: node_modules
	npm list express || npm install express
	npm list connect-timeout || npm install connect-timeout

.PHONY: ruby-dependencies
ruby-dependencies:
	gem install --no-doc sinatra
	gem install --no-doc json

.PHONY: setup
setup: python-dependencies python3-dependencies js-dependencies ruby-dependencies install-quark

.PHONY: install-quark
install-quark:
	which quark || \
		curl -# -L https://raw.githubusercontent.com/datawire/quark/master/install.sh | \
		bash -s -- -q `cat QUARK_VERSION.txt`

.PHONY: install-mdk
install-mdk: packages $(wildcard javascript/**/*)
	virtualenv/bin/pip install --upgrade dist/datawire_mdk-*-py2*-none-any.whl
	virtualenv3/bin/pip install --upgrade dist/datawire_mdk-*-*py3-none-any.whl
	django110env/bin/pip install --upgrade dist/datawire_mdk-*-*py3-none-any.whl
	gem install --no-doc dist/datawire_mdk-*.gem
	gem install --no-doc dist/rack*.gem
	gem install --no-doc dist/faraday*.gem
	npm install output/js/mdk-2.0
	npm install javascript/datawire_mdk_express/
	npm install javascript/datawire_mdk_request/
	cd output/java/mdk-2.0 && mvn install

.PHONY: setup-docker
setup-docker: docker
	# Set up docker image for a local websocket echo server
	docker build -t datawire/websocket-echo docker/websocket-echo
	docker tag datawire/websocket-echo \
		datawire/websocket-echo:`node -e "console.log(require('./docker/websocket-echo/package.json').version)"`
	# Set up special docker image for `quark run`ning tests
	# Need `quark install --online` and additional build environment stuff for MDK Runtime
	docker build -t datawire/mdk-quark-run docker/mdk-quark-run
	docker tag datawire/mdk-quark-run datawire/mdk-quark-run:`sed s/v//g < QUARK_VERSION.txt`

.PHONY: test
test: install-mdk test-python test-python3

.PHONY: guard-token
guard-token:
	@ if [ "${DATAWIRE_TOKEN}" = "" ]; then \
	    echo "DATAWIRE_TOKEN not set"; \
	    exit 1; \
	fi

.PHONY: test-python
test-python:
	# Functional tests don't benefit from being run in another language, so
	# we only run them under Python 3:
	virtualenv/bin/py.test -n 4 -v unittests

.PHONY: test-python3
test-python3: guard-token
	virtualenv3/bin/py.test -n 4 -v --timeout=180 --timeout_method=thread unittests functionaltests

release-minor:
	virtualenv/bin/python scripts/release.py minor

release-patch:
	virtualenv/bin/python scripts/release.py patch

# Packaging commands:
output: $(wildcard quark/*.q) $(wildcard python/*.py)
	rm -rf output output.temp quark/*.qc quark/tests/*.qc
	# Use installed Quark if we don't already have quark cli in PATH:
	which quark || source ~/.quark/config.sh; quark compile --include-stdlib -o output.temp quark/mdk-2.0.q
	cp python/*.py output.temp/py/mdk-2.0/mdk/
	mv output.temp output

packages: python-packages ruby-packages javascript-packages java-packages

python-packages: output
	python scripts/build-packages.py py output/py/mdk-2.0 dist/

ruby-packages: output $(wildcard ruby/**)
	python scripts/build-packages.py rb output/rb/mdk-2.0 dist/
	cd ruby/rack-mdk && gem build rack-mdk.gemspec
	mv ruby/rack-mdk/*.gem dist/
	cd ruby/faraday_mdk && gem build faraday_mdk.gemspec
	mv ruby/faraday_mdk/*.gem dist

javascript-packages: output $(wildcard javascript/**)
	python scripts/build-packages.py js output/js/mdk-2.0 dist/

java-packages: output
	python scripts/build-packages.py java output/java/mdk-2.0 dist/


# Package upload commands
.PHONY: upload-packages
upload-packages: packages
	source virtualenv/bin/activate; python scripts/upload.py
