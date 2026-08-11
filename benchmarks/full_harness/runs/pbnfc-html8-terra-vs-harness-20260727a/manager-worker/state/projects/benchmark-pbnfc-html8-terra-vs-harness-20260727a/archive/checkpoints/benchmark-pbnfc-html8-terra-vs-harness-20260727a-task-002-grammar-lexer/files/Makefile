CC ?= cc

CPPFLAGS := -Iinclude
CFLAGS := -std=c11 -Wall -Wextra -Werror -pedantic -pthread
LDFLAGS :=
LDLIBS :=

TARGET := bin/pbnfc
SOURCES := src/main.c src/diagnostics.c src/grammar_lexer.c
OBJECTS := $(patsubst src/%.c,build/%.o,$(SOURCES))
DEPFILES := $(OBJECTS:.o=.d)
GRAMMAR_LEXER_SMOKE := build/grammar-lexer-core-smoke

.PHONY: all clean test-grammar-lexer-core

all: $(TARGET)

test-grammar-lexer-core: $(GRAMMAR_LEXER_SMOKE)
	./$(GRAMMAR_LEXER_SMOKE)

$(GRAMMAR_LEXER_SMOKE): tests/grammar_lexer_smoke.c build/grammar_lexer.o build/diagnostics.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(TARGET): $(OBJECTS) | bin
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

build/%.o: src/%.c | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

bin build:
	mkdir -p $@

-include $(DEPFILES)

clean:
	rm -rf build bin
