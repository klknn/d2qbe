.PHONY: all test clean unittest test-integration test-regression test-selfhost unittest-frontend unittest-backend benchmark

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

dqbe: source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/regalloc.d source/dqbe/codegen.d source/dqbe/sysv.d source/dqbe/win64.d source/dqbe/app.d test/tmp_ext_all.d
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

ifeq ($(OS),Windows_NT)
test: unittest test-integration-dqbe test-regression test-selfhost-dqbe
	dub test
	@echo "All tests passed successfully!"
else
test: unittest test-integration test-integration-dqbe test-regression test-selfhost test-selfhost-dqbe
	dub test
	@echo "All tests passed successfully!"
endif

test-integration: d2qbe qbe/qbe ext.$(OBJ_EXT)
	./test/run.sh

test-integration-dqbe: d2qbe dqbe ext.$(OBJ_EXT)
	QBE=./dqbe ./test/run.sh

test-regression: dqbe
	@ARCH=$$(uname -m); \
	if [ "$$ARCH" = "x86_64" ] || [ "$$ARCH" = "amd64" ]; then \
		./dqbe < test/liveness_bug.ssa > tmp_liveness_bug.s && \
		cc -o tmp_liveness_bug tmp_liveness_bug.s && \
		./tmp_liveness_bug && \
		rm -f tmp_liveness_bug.s tmp_liveness_bug; \
	else \
		echo "Skipping test-regression: dqbe only supports x86_64 architecture (host is $$ARCH)"; \
	fi

test-selfhost: d2qbe dqbe qbe/qbe ext.$(OBJ_EXT)
	./test/self_host.sh
	./test/self_host_dqbe.sh

test-selfhost-dqbe: d2qbe dqbe ext.$(OBJ_EXT)
	./test/self_host_dqbe.sh

benchmark: d2qbe dqbe qbe/qbe
	./test/bench_all.sh
	./test/bench_self_host.sh

unittest: unittest-frontend unittest-backend

unittest-frontend:
	$(DC) -g -w -Isource -unittest -main source/d2qbe/tokenize.d source/d2qbe/config.d source/d2qbe/parse.d source/d2qbe/codegen.d source/d2qbe/c_declarations.d test/ext.d -of=unittest_frontend
	./unittest_frontend
	rm -f unittest_frontend

unittest-backend:
	$(DC) -g -w -Isource -unittest -main source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/regalloc.d source/dqbe/codegen.d source/dqbe/sysv.d source/dqbe/win64.d test/tmp_ext_all.d -of=unittest_backend
	./unittest_backend
	rm -f unittest_backend

clean:
	rm -f d2qbe dqbe *.o *.obj *.di tmp* unittest_frontend unittest_backend

qbe/qbe:
	make -C qbe

qbe/minic/minic:
	make -C qbe/minic
