SHELL=/bin/bash

.PHONY: all
all: test
	shards build


.PHONY: test
test:
	crystal spec --error-trace -- --chaos

.PHONY: demo
demo:
	crystal run demo/run.cr --error-trace
