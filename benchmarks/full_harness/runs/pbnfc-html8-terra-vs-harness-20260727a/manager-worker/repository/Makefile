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
PARALLEL_CLOSURE_CORE_SMOKE := build/parallel-closure-core-smoke
PARALLEL_SCANNING_CORE_SMOKE := build/parallel-scanning-core-smoke
WORKER_STATS_CORE_SMOKE := build/worker-stats-core-smoke
HIERARCHICAL_MARKUP_CORE_SMOKE := build/hierarchical-markup-core-smoke
HIERARCHICAL_REJECTION_CORE_SMOKE := build/hierarchical-rejection-core-smoke
HIERARCHICAL_STRESS_CORE_SMOKE := build/hierarchical-stress-core-smoke

.PHONY: all clean test test-grammar-lexer-core test-grammar-ast-core test-markup-lexer-core test-chart-core test-worker-pool-core test-sequential-recognizer test-parallel-closure-core test-parallel-scanning-core test-worker-stats-core test-hierarchical-markup-core test-hierarchical-rejection-core test-hierarchical-stress-core

all: $(TARGET)

test: test-grammar-lexer-core test-grammar-ast-core test-markup-lexer-core test-chart-core test-worker-pool-core test-sequential-recognizer test-parallel-closure-core test-parallel-scanning-core test-worker-stats-core test-hierarchical-markup-core test-hierarchical-rejection-core test-hierarchical-stress-core
	@echo "All focused tests passed."

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

test-parallel-closure-core: $(PARALLEL_CLOSURE_CORE_SMOKE)
	./$(PARALLEL_CLOSURE_CORE_SMOKE)

test-parallel-scanning-core: $(PARALLEL_SCANNING_CORE_SMOKE)
	./$(PARALLEL_SCANNING_CORE_SMOKE)

test-worker-stats-core: $(WORKER_STATS_CORE_SMOKE) $(TARGET)
	./$(WORKER_STATS_CORE_SMOKE)

test-hierarchical-markup-core: $(HIERARCHICAL_MARKUP_CORE_SMOKE) $(TARGET)
	./$(HIERARCHICAL_MARKUP_CORE_SMOKE)

test-hierarchical-rejection-core: $(HIERARCHICAL_REJECTION_CORE_SMOKE) $(TARGET)
	./$(HIERARCHICAL_REJECTION_CORE_SMOKE)

test-hierarchical-stress-core: $(HIERARCHICAL_STRESS_CORE_SMOKE) $(TARGET)
	./$(HIERARCHICAL_STRESS_CORE_SMOKE)

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

$(SEQUENTIAL_RECOGNIZER_SMOKE): tests/sequential_recognizer_smoke.c build/recognizer.o build/chart.o build/worker_pool.o build/grammar_ast.o build/grammar_lexer.o build/markup_lexer.o build/diagnostics.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(PARALLEL_CLOSURE_CORE_SMOKE): tests/parallel_closure_smoke.c build/recognizer.o build/chart.o build/worker_pool.o build/grammar_ast.o build/grammar_lexer.o build/markup_lexer.o build/diagnostics.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(PARALLEL_SCANNING_CORE_SMOKE): tests/parallel_scanning_smoke.c build/recognizer.o build/chart.o build/worker_pool.o build/grammar_ast.o build/grammar_lexer.o build/markup_lexer.o build/diagnostics.o | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(WORKER_STATS_CORE_SMOKE): tests/worker_stats_smoke.c $(TARGET) | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

$(HIERARCHICAL_MARKUP_CORE_SMOKE): tests/hierarchical_markup_smoke.c $(TARGET) | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

$(HIERARCHICAL_REJECTION_CORE_SMOKE): tests/hierarchical_rejection_smoke.c $(TARGET) | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

$(HIERARCHICAL_STRESS_CORE_SMOKE): tests/hierarchical_stress_smoke.c $(TARGET) | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

$(TARGET): $(OBJECTS) | bin
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

build/%.o: src/%.c | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

bin build:
	mkdir -p $@

-include $(DEPFILES)

clean:
	rm -rf build bin
