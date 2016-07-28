.PHONY: default
default:
	echo "Run 'make quark_test' or 'make native_test'."


.PHONY: quark_test
quark_test:
	quark run --java quark/tests/mdk_test.q
	quark run --javascript quark/tests/mdk_test.q
	quark run --python quark/tests/mdk_test.q
	quark run --ruby quark/tests/mdk_test.q

.PHONY: native_test
native_test:
	python -m unittest discover tests
