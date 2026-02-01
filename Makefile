.PHONY: test clean

DC=ldc2
DFLAGS=-g -betterC -I source
OBJS=parse.o codegen.o app.o

%.o: source/d2qbe/%.d
	$(DC) $(DFLAGS) -c $<

d2qbe: $(OBJS)
	$(DC) $(DFLAGS) $(OBJS) -of=$@

test: d2qbe qbe/qbe
	./test/run.sh

clean:
	rm -f d2qbe *.o tmp*

qbe/qbe:
	make -C qbe

qbe/minic/minic:
	make -C qbe/minic
