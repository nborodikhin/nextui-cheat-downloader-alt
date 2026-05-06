NIM        ?= nim
BINARY      = cheat_manager
BINARY_COV  = cheat_manager_cov
MINIZ_VER  ?= 3.1.1
MINIZ_FLAGS = -d:minizDir=workspace/miniz-$(MINIZ_VER) --passC:-Iworkspace/miniz-$(MINIZ_VER)
NIMCACHE    = nimcache

ifdef COVERAGE
COV_FLAGS  = --passC:--coverage --passL:--coverage --lineDir:on --nimcache:$(NIMCACHE)
E2E_DEP    = $(BINARY_COV)
E2E_FLAGS  = -d:BINARY=$(CURDIR)/$(BINARY_COV)
else
COV_FLAGS  =
E2E_DEP    = $(BINARY)
E2E_FLAGS  =
endif

GCOVR_FLAGS = --filter cheat_manager.nim --gcov-ignore-errors=no_working_dir_found
GCDA        = $(NIMCACHE)/@mcheat_manager.nim.c.gcda

.PHONY: all build test test-e2e test-all coverage launch-test clean

all: build

build:
	./build-binary.sh host debug

test:
	$(NIM) c $(COV_FLAGS) -r --path:. $(MINIZ_FLAGS) cheat_manager_test.nim

$(BINARY_COV): cheat_manager.nim
	$(NIM) c --passC:--coverage --passL:--coverage --lineDir:on --path:. $(MINIZ_FLAGS) --nimcache:$(NIMCACHE) -o:$(BINARY_COV) cheat_manager.nim

test-e2e: $(E2E_DEP)
	$(NIM) c -r --path:. $(MINIZ_FLAGS) $(E2E_FLAGS) cheat_manager_e2e.nim

test-all: test test-e2e

coverage:
	rm -rf $(NIMCACHE)
	$(MAKE) test test-e2e COVERAGE=true
	mkdir -p coverage
	gcovr $(GCOVR_FLAGS) $(GCDA) --print-summary
	gcovr $(GCOVR_FLAGS) $(GCDA) --html --html-details -o coverage/index.html

launch-test: build
	./launch-test.sh

clean:
	rm -f $(BINARY) $(BINARY_COV) cheat_manager_test cheat_manager_e2e
