.PHONY: default
default:
	echo "Run 'make test' to run tests."

.PHONY: setup
setup:
	pip install hypothesis

.PHONY: test
test:
	python -m unittest discover -v
