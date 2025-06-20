SHELL=/bin/bash

.PHONY: all
all: test
	shards build


.PHONY: test
test:
	./scripts/test-ci.sh

.PHONY: demo
demo:
	crystal run demo/run.cr --error-trace
