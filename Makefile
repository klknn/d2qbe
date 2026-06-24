.PHONY: all test clean unittest test-integration test-regression test-selfhost unittest-frontend unittest-backend

DC=ldc2
DFLAGS=-g -w -betterC -Isource
OBJS=tokenize.o config.o parse.o codegen.o c_declarations.o app.o

all: d2qbe dqbe qbe/qbe

d2qbe: $(OBJS) ext.o
	$(DC) $(DFLAGS) $(OBJS) ext.o -of=$@

dqbe: source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/regalloc.d source/dqbe/codegen.d source/dqbe/app.d test/tmp_ext_all.d
	$(DC) $(DFLAGS) $^ -of=$@

%.o: source/d2qbe/%.d
	$(DC) $(DFLAGS) -c $<

config.o: source/d2qbe/config.d

parse.o: source/d2qbe/parse.d tokenize.o config.o

codegen.o: source/d2qbe/codegen.d parse.o tokenize.o config.o

c_declarations.o: source/d2qbe/c_declarations.d

app.o: source/d2qbe/app.d codegen.o parse.o tokenize.o c_declarations.o config.o

ext.o: test/ext.d
	$(DC) $(DFLAGS) -c $<

test: unittest test-integration test-regression test-selfhost
	@echo "All tests passed successfully!"

test-integration: d2qbe qbe/qbe ext.o
	./test/run.sh

test-regression: dqbe
	./dqbe < test/liveness_bug.ssa > tmp_liveness_bug.s
	cc -o tmp_liveness_bug tmp_liveness_bug.s
	./tmp_liveness_bug
	rm -f tmp_liveness_bug.s tmp_liveness_bug

test-selfhost: d2qbe dqbe
	./test/self_host_dqbe.sh

unittest: unittest-frontend unittest-backend

unittest-frontend:
	$(DC) $(DFLAGS) -unittest -main source/d2qbe/tokenize.d source/d2qbe/config.d source/d2qbe/parse.d source/d2qbe/codegen.d source/d2qbe/c_declarations.d test/ext.d -of=unittest_frontend
	./unittest_frontend
	rm -f unittest_frontend

unittest-backend:
	$(DC) $(DFLAGS) -unittest -main source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/regalloc.d source/dqbe/codegen.d test/tmp_ext_all.d -of=unittest_backend
	./unittest_backend
	rm -f unittest_backend

clean:
	rm -f d2qbe dqbe *.o *.di tmp* unittest_frontend unittest_backend

qbe/qbe:
	make -C qbe

qbe/minic/minic:
	make -C qbe/minic
