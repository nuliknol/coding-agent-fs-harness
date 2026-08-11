CC ?= cc

CPPFLAGS := -Iinclude
CFLAGS := -std=c11 -Wall -Wextra -Werror -pedantic -pthread
LDFLAGS :=
LDLIBS :=

TARGET := bin/pbnfc
SOURCES := src/main.c src/diagnostics.c src/grammar_lexer.c src/grammar_ast.c src/markup_lexer.c src/chart.c src/worker_pool.c src/recognizer.c
OBJECTS := $(patsubst src/%.c,build/%.o,$(SOURCES))
DEPFILES := $(OBJECTS:.o=.d)
GRAMMAR_LEXER_SMOKE := build/grammar-lexer-core-smoke
GRAMMAR_AST_SMOKE := build/grammar-ast-core-smoke
MARKUP_LEXER_SMOKE := build/markup-lexer-core-smoke
CHART_CORE_SMOKE := build/chart-core-smoke
SEQUENTIAL_RECOGNIZER_SMOKE := build/sequential-recognizer-smoke
WORKER_POOL_CORE_SMOKE := build/worker-pool-core-smoke

.PHONY: all clean test-grammar-lexer-core test-grammar-ast-core test-markup-lexer-core test-chart-core test-worker-pool-core test-sequential-recognizer

all: $(TARGET)

test-grammar-lexer-core: $(GRAMMAR_LEXER_SMOKE)
	./$(GRAMMAR_LEXER_SMOKE)

test-grammar-ast-core: $(GRAMMAR_AST_SMOKE)
	./$(GRAMMAR_AST_SMOKE)

test-markup-lexer-core: $(MARKUP_LEXER_SMOKE)
	./$(MARKUP_LEXER_SMOKE)

test-chart-core: $(CHART_CORE_SMOKE)
	./$(CHART_CORE_SMOKE)

test-worker-pool-core: $(WORKER_POOL_CORE_SMOKE)
	./$(WORKER_POOL_CORE_SMOKE)

test-sequential-recognizer: $(SEQUENTIAL_RECOGNIZER_SMOKE)
	./$(SEQUENTIAL_RECOGNIZER_SMOKE)

$(GRAMMAR_LEXER_SMOKE): tests/grammar_lexer_smoke.c build/grammar_lexer.o build/diagnostics.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(GRAMMAR_AST_SMOKE): tests/grammar_ast_smoke.c build/grammar_ast.o build/grammar_lexer.o build/diagnostics.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(MARKUP_LEXER_SMOKE): tests/markup_lexer_smoke.c build/markup_lexer.o build/diagnostics.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(CHART_CORE_SMOKE): tests/chart_core_smoke.c build/chart.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(WORKER_POOL_CORE_SMOKE): tests/worker_pool_core_smoke.c build/worker_pool.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(SEQUENTIAL_RECOGNIZER_SMOKE): tests/sequential_recognizer_smoke.c build/recognizer.o build/chart.o build/grammar_ast.o build/grammar_lexer.o build/markup_lexer.o build/diagnostics.o | build
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
