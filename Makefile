DC=ldc2
DFLAGS=-g

d2qbe: source/app.d
	$(DC) $(DFLAGS) $< -of=$@

test: d2qbe
	./test/run.sh

clean:
	rm -f d2qbe *.o tmp*

.PHONY: test clean
