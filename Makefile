SHELL=/bin/bash

.PHONY: all
all: test
	shards build


tests:=$(shell find ./test -iname "*_test.cr")
.PHONY: test
test:
	crystal run --error-trace test/test_helper.cr ${tests} -- --chaos

.PHONY: demo
demo:
	crystal run demo/run.cr --error-trace
