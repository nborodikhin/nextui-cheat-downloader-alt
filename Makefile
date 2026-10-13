# Shortcuts for ./dev, the main entry point. Run ./dev --help for the rest.

.PHONY: all build test test-e2e test-all coverage launch-test clean

all: build

build:
	./dev build

test:
	./dev test unit

test-e2e:
	./dev test e2e

test-all:
	./dev test

coverage:
	./dev test --coverage

launch-test: build
	./launch-test.sh

clean:
	./dev clean
