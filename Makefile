.PHONY: default
default:
	echo "Run 'make test' to run tests."

.PHONY: test
test:
	python -m unittest discover -v tests
