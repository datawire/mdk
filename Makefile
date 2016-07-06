.PHONY: default
default:
	echo "Run 'make quark_test' or 'make native_test'."


.PHONY: quark_test
quark_test:
	quark run --java quark/mdk_test.q
	quark run --javascript quark/mdk_test.q
	quark run --python quark/mdk_test.q
	quark run --ruby quark/mdk_test.q

.PHONY: native_test
native_test:
	python -m unittest discover tests
