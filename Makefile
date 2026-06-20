.PHONY: all test clean unittest

DC=ldc2
DFLAGS=-g -w -betterC -Isource
OBJS=tokenize.o parse.o codegen.o app.o

all: d2qbe qbe/qbe

d2qbe: $(OBJS) ext.o
	$(DC) $(DFLAGS) $(OBJS) ext.o -of=$@

%.o: source/d2qbe/%.d
	$(DC) $(DFLAGS) -c $<

parse.o: source/d2qbe/parse.d tokenize.o

codegen.o: source/d2qbe/codegen.d parse.o tokenize.o

app.o: source/d2qbe/app.d codegen.o parse.o tokenize.o

ext.o: test/ext.d
	$(DC) $(DFLAGS) -c $<

test: d2qbe qbe/qbe ext.o
	./test/run.sh

unittest:
	$(DC) -unittest -main source/d2qbe/tokenize.d source/d2qbe/parse.d source/d2qbe/codegen.d test/ext.d -of=unittest_runner
	./unittest_runner
	rm -f unittest_runner

clean:
	rm -f d2qbe *.o *.di tmp*

qbe/qbe:
	make -C qbe

qbe/minic/minic:
	make -C qbe/minic
