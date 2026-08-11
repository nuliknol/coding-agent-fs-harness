#ifndef PBNFC_RECOGNIZER_H
#define PBNFC_RECOGNIZER_H

#include "grammar_ast.h"
#include "markup_lexer.h"

#include <stdbool.h>
#include <stddef.h>

typedef enum {
    PBNFC_RECOGNITION_ERROR = -1,
    PBNFC_RECOGNITION_REJECTED = 0,
    PBNFC_RECOGNITION_ACCEPTED = 1
} PbnfcRecognitionResult;

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

#endif
