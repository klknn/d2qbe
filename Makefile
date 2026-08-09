.PHONY: all test clean unittest test-integration test-regression test-selfhost unittest-frontend unittest-backend test-dqbe-abi test-dqbe-wasm test-wasm-browser-assets test-wasm4-carts wasm-browser-test wasm-browser-demo wasm-browser-game wasm4-carts wasm4-tetromino wasm4-minicraft wasm4-flight wasm4-snake benchmark

DC=ldc2
DFLAGS=-g -w -betterC -Isource

ifeq ($(OS),Windows_NT)
    OBJ_EXT = obj
else
    OBJ_EXT = o
endif

OBJS=tokenize.$(OBJ_EXT) config.$(OBJ_EXT) parse.$(OBJ_EXT) codegen.$(OBJ_EXT) c_declarations.$(OBJ_EXT) app.$(OBJ_EXT)

all: d2qbe dqbe qbe/qbe

d2qbe: $(OBJS) ext.$(OBJ_EXT)
	$(DC) $(DFLAGS) $(OBJS) ext.$(OBJ_EXT) -of=$@

dqbe: source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/regalloc.d source/dqbe/codegen.d source/dqbe/wasm.d source/dqbe/sysv.d source/dqbe/win64.d source/dqbe/arm64_abi.d source/dqbe/app.d test/tmp_ext_all.d
	$(DC) $(DFLAGS) $^ -of=$@

%.$(OBJ_EXT): source/d2qbe/%.d
	$(DC) $(DFLAGS) -c $<

config.$(OBJ_EXT): source/d2qbe/config.d

parse.$(OBJ_EXT): source/d2qbe/parse.d tokenize.$(OBJ_EXT) config.$(OBJ_EXT)

codegen.$(OBJ_EXT): source/d2qbe/codegen.d parse.$(OBJ_EXT) tokenize.$(OBJ_EXT) config.$(OBJ_EXT)

c_declarations.$(OBJ_EXT): source/d2qbe/c_declarations.d

app.$(OBJ_EXT): source/d2qbe/app.d codegen.$(OBJ_EXT) parse.$(OBJ_EXT) tokenize.$(OBJ_EXT) c_declarations.$(OBJ_EXT) config.$(OBJ_EXT)

ext.$(OBJ_EXT): test/ext.d
	$(DC) $(DFLAGS) -c $<

ext.arm64.o: test/ext.d
	$(DC) -mtriple=aarch64-linux-gnu $(DFLAGS) -c $< -of=$@

ifeq ($(OS),Windows_NT)
test: unittest test-integration-dqbe test-dqbe-abi test-dqbe-wasm test-wasm-browser-assets test-regression test-selfhost-dqbe
else
test: unittest test-integration test-integration-dqbe test-dqbe-abi test-dqbe-wasm test-wasm-browser-assets test-wasm4-carts test-regression test-selfhost test-selfhost-dqbe
endif

test-integration: d2qbe qbe/qbe ext.$(OBJ_EXT)
	./test/run.sh

test-integration-dqbe: d2qbe dqbe ext.$(OBJ_EXT)
	QBE=./dqbe ./test/run.sh

test-regression: dqbe
	./test/regression.sh

test-dqbe-abi: dqbe
	./test/dqbe_abi_test.sh

test-dqbe-wasm: d2qbe dqbe
	./test/dqbe_wasm_test.sh

test-wasm-browser-assets: d2qbe dqbe
	./test/wasm_browser_assets_test.sh

test-wasm4-carts: d2qbe dqbe
	sh ./test/wasm4_carts_test.sh

wasm-browser-test: d2qbe dqbe
	./test/wasm_browser/build.sh test
	./test/wasm_browser/serve.sh test

wasm-browser-demo: d2qbe dqbe
	./test/wasm_browser/build.sh demo
	./test/wasm_browser/serve.sh demo

wasm-browser-game: d2qbe dqbe
	./test/wasm_browser/build.sh game
	./test/wasm_browser/serve.sh game

wasm4-carts: d2qbe dqbe
	sh ./demo/wasm4/build.sh all

wasm4-tetromino: wasm4-carts
	w4 run tmp_wasm4/tetromino.wasm

wasm4-minicraft: wasm4-carts
	w4 run tmp_wasm4/minicraft.wasm

wasm4-flight: wasm4-carts
	w4 run tmp_wasm4/flight.wasm

wasm4-snake: wasm4-carts
	w4 run tmp_wasm4/snake.wasm

test-selfhost: d2qbe qbe/qbe ext.$(OBJ_EXT)
	./test/self_host.sh

test-selfhost-dqbe: d2qbe dqbe ext.$(OBJ_EXT)
	./test/self_host_dqbe.sh

test-qemu-arm64: d2qbe dqbe ext.arm64.o
	TARGET_ARCH=arm64 QBE=./dqbe ./test/run.sh

test-qemu-arm64-qbe: d2qbe qbe/qbe ext.arm64.o
	TARGET_ARCH=arm64 QBE=./qbe/qbe ./test/run.sh

benchmark: d2qbe dqbe qbe/qbe
	./test/bench_all.sh
	./test/bench_self_host.sh

unittest: unittest-frontend unittest-backend
	dub test

unittest-frontend:
	$(DC) -g -w -Isource -unittest -main source/d2qbe/tokenize.d source/d2qbe/config.d source/d2qbe/parse.d source/d2qbe/codegen.d source/d2qbe/c_declarations.d test/ext.d -of=unittest_frontend
	./unittest_frontend
	rm -f unittest_frontend

unittest-backend:
	$(DC) -g -w -Isource -unittest -main source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/regalloc.d source/dqbe/codegen.d source/dqbe/wasm.d source/dqbe/sysv.d source/dqbe/win64.d source/dqbe/arm64_abi.d test/tmp_ext_all.d -of=unittest_backend
	./unittest_backend
	rm -f unittest_backend

clean:
	rm -f d2qbe dqbe *.o *.obj *.di tmp* unittest_frontend unittest_backend

qbe/qbe:
	make -C qbe

qbe/minic/minic:
	make -C qbe/minic
