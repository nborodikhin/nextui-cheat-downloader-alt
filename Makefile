NIM      ?= nim
BINARY    = cheat_manager
NIMCACHE  = nimcache

ifdef COVERAGE
COV_FLAGS = --passC:--coverage --passL:--coverage --lineDir:on
else
COV_FLAGS =
endif

GCOVR_FLAGS = --filter cheat_manager.nim --gcov-ignore-errors=no_working_dir_found --gcov-ignore-errors=source_not_found --object-directory $(NIMCACHE)
GCDA        = $(NIMCACHE)/@mcheat_manager.nim.c.gcda

BINARIES = cheat_manager cheat_manager_test cheat_manager_e2e

.PHONY: all build test test-e2e test-all coverage launch-test clean

all: build

build: cheat_manager

$(BINARIES): %: %.nim
	SOURCE=$< EXTRA_NIM_FLAGS="$(COV_FLAGS)" ./build-binary.sh host debug

test: cheat_manager_test
	./cheat_manager_test

test-e2e: cheat_manager cheat_manager_e2e
	CHEAT_MANAGER_BIN=./cheat_manager ./cheat_manager_e2e

test-all: test test-e2e

coverage:
	$(MAKE) clean test test-e2e COVERAGE=true
	mkdir -p coverage
	gcovr $(GCOVR_FLAGS) $(GCDA) --print-summary
	gcovr $(GCOVR_FLAGS) $(GCDA) --html --html-details -o coverage/index.html

launch-test: build
	./launch-test.sh

clean:
	rm -rf $(NIMCACHE)
	rm -f $(BINARIES)
