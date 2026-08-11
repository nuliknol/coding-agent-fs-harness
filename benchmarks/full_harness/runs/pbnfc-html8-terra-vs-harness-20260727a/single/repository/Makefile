CC ?= cc
CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -pthread -Iinclude
OBJ = src/main.o src/diag.o src/grammar.o src/markup.o src/pool.o

.PHONY: all clean test
all: bin/pbnfc

bin/pbnfc: $(OBJ)
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $(OBJ)

src/%.o: src/%.c include/pbnfc.h
	$(CC) $(CFLAGS) -c -o $@ $<

test: all
	./tests/run.sh

clean:
	rm -f $(OBJ) bin/pbnfc
