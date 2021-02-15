SHELL=/bin/bash

.PHONY: all
all: test
	crystal build -p src/mosquito.cr -o bin/mosquito


tests:=$(shell find ./test -iname "*_test.cr")
.PHONY: test
test:
	crystal run test/test_helper.cr ${tests} -- --chaos

.PHONY: demo
demo:
	crystal run demo/run.cr
