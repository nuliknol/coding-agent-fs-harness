#ifndef PBNFC_RECOGNIZER_H
#define PBNFC_RECOGNIZER_H

#include "grammar_ast.h"
#include "markup_lexer.h"
#include "worker_pool.h"

#include <stdbool.h>
#include <stddef.h>

typedef enum {
    PBNFC_RECOGNITION_ERROR = -1,
    PBNFC_RECOGNITION_REJECTED = 0,
    PBNFC_RECOGNITION_ACCEPTED = 1
} PbnfcRecognitionResult;

typedef struct {
    size_t rounds;
    size_t tasks[PBNFC_WORKER_POOL_SIZE];
    size_t workers;
    size_t active_workers;
} PbnfcRecognitionStats;

/*
 * Recognize one complete markup token stream with a validated grammar.
 * The token array excludes the lexer's EOF token and remains caller-owned.
 * When start_name is NULL, the grammar's %start rule is used.
 */
PbnfcRecognitionResult pbnfc_recognize_sequential(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name);

/*
 * Recognize as above and emit one deterministic REJECT diagnostic when the
 * input is syntactically valid but does not match the grammar. The diagnostic
 * context is borrowed and may be NULL to suppress output.
 */
PbnfcRecognitionResult pbnfc_recognize_sequential_with_diagnostics(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name,
    const PbnfcDiagnosticContext *diagnostics);

/*
 * Recognize with the persistent eight-worker chart pool. The optional stats
 * structure is filled with deterministic generation and per-worker work
 * counts; the caller owns it and may pass NULL when statistics are not needed.
 */
PbnfcRecognitionResult pbnfc_recognize_parallel(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name,
    PbnfcRecognitionStats *stats);

PbnfcRecognitionResult pbnfc_recognize_parallel_with_diagnostics(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name,
    const PbnfcDiagnosticContext *diagnostics,
    PbnfcRecognitionStats *stats);

#endif
