.PHONY: test clean

DC=ldc2
DFLAGS=-g -betterC -I source
OBJS=parse.o codegen.o app.o

d2qbe: $(OBJS)
	$(DC) $(DFLAGS) $(OBJS) -of=$@

%.o: source/d2qbe/%.d
	$(DC) $(DFLAGS) -c $<

codegen.o: source/d2qbe/codegen.d parse.o

app.o: source/d2qbe/app.d codegen.o parse.o

test: d2qbe qbe/qbe
	./test/run.sh

clean:
	rm -f d2qbe *.o *.di tmp*

qbe/qbe:
	make -C qbe

qbe/minic/minic:
	make -C qbe/minic
