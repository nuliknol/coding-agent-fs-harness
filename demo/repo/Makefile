CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -Iinclude

.PHONY: all test clean

all: test_calc

test_calc: src/calc.c tests/test_calc.c include/calc.h
	$(CC) $(CFLAGS) src/calc.c tests/test_calc.c -o test_calc

test: test_calc
	./test_calc

clean:
	rm -f test_calc
