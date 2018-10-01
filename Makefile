.PHONY: all
all: test
	crystal build -p src/mosquito.cr -o bin/mosquito

.PHONY: test
test:
	crystal run test/test_helper.cr test/**/*_test.cr -- --chaos

.PHONY: demo
demo:
	crystal run demo/run.cr
