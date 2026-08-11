CC = cc
CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -pthread -Iinclude
LDFLAGS = -pthread

SOURCES = src/main.c src/diagnostics.c src/grammar.c src/markup.c src/pool.c src/recognizer.c
OBJECTS = $(SOURCES:.c=.o)

bin/pbnfc: $(OBJECTS)
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $(OBJECTS) $(LDFLAGS)

all: bin/pbnfc

clean:
	rm -f $(OBJECTS) bin/pbnfc

test: bin/pbnfc
	@tests/smoke.sh

.PHONY: all clean test
