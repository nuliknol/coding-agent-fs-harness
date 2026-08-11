CC = cc
CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -Iinclude
BIN = bin/bnfc
OBJ = src/bnfc.o
.PHONY: all clean test
all: $(BIN)
$(BIN): $(OBJ) | bin
	$(CC) $(CFLAGS) -o $@ $(OBJ)
src/bnfc.o: src/bnfc.c include/bnfc.h
	$(CC) $(CFLAGS) -c -o $@ $<
bin:
	mkdir -p bin
test: $(BIN)
	sh tests/run.sh
clean:
	rm -f $(OBJ) $(BIN)
