NIM        ?= nim
BINARY      = cheat_manager
MINIZ_VER  ?= 3.1.1
MINIZ_FLAGS = -d:minizDir=workspace/miniz-$(MINIZ_VER) --passC:-Iworkspace/miniz-$(MINIZ_VER)

.PHONY: all build test coverage launch-test clean

all: build

build:
	./build-binary.sh host debug

test:
	$(NIM) c -r --path:. $(MINIZ_FLAGS) cheat_manager_test.nim

NIMCACHE = nimcache

coverage:
	find $(NIMCACHE) -name "*.gcda" -delete 2>/dev/null; true
	$(NIM) c --passC:--coverage --passL:--coverage --lineDir:on -r --path:. $(MINIZ_FLAGS) --nimcache:$(NIMCACHE) cheat_manager_test.nim
	mkdir -p coverage
	gcovr --filter cheat_manager.nim --gcov-ignore-errors=no_working_dir_found $(NIMCACHE)/@mcheat_manager.nim.c.gcda --print-summary
	gcovr --filter cheat_manager.nim --gcov-ignore-errors=no_working_dir_found $(NIMCACHE)/@mcheat_manager.nim.c.gcda --html --html-details -o coverage/index.html

launch-test: build
	./launch-test.sh

clean:
	rm -f $(BINARY) cheat_manager_test
