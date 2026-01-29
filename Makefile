.PHONY: test clean

DC=ldc2
DFLAGS=-g -betterC

d2qbe: source/app.d
	$(DC) $(DFLAGS) $< -of=$@

test: d2qbe qbe/qbe
	./test/run.sh

clean:
	rm -f d2qbe *.o tmp*

qbe/qbe:
	make -C qbe

qbe/minic/minic:
	make -C qbe/minic
