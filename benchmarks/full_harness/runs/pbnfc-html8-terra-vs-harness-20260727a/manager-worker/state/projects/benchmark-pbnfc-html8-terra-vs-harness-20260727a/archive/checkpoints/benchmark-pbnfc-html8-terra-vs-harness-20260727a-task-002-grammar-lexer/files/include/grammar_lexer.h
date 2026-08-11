#ifndef PBNFC_GRAMMAR_LEXER_H
#define PBNFC_GRAMMAR_LEXER_H

#include "diagnostics.h"

#include <stdbool.h>
#include <stddef.h>

typedef enum {
    PBNFC_GRAMMAR_TOKEN_EOF = 0,
    PBNFC_GRAMMAR_TOKEN_START_DIRECTIVE,
    PBNFC_GRAMMAR_TOKEN_TOKEN_DIRECTIVE,
    PBNFC_GRAMMAR_TOKEN_IDENTIFIER,
    PBNFC_GRAMMAR_TOKEN_ASSIGN,
    PBNFC_GRAMMAR_TOKEN_PIPE,
    PBNFC_GRAMMAR_TOKEN_SEMICOLON
} PbnfcGrammarTokenKind;

/*
 * A token is a non-owning view into the source buffer supplied to the lexer.
 * The caller owns that buffer and must keep it alive while using the token.
 */
typedef struct {
    PbnfcGrammarTokenKind kind;
    PbnfcLocation location;
    const char *text;
    size_t length;
} PbnfcGrammarToken;

typedef struct {
    const char *source;
    size_t length;
    size_t offset;
    size_t line;
    size_t column;
    const PbnfcDiagnosticContext *diagnostics;
    bool failed;
} PbnfcGrammarLexer;

void pbnfc_grammar_lexer_init(PbnfcGrammarLexer *lexer,
                              const char *source,
                              size_t length,
                              const PbnfcDiagnosticContext *diagnostics);

/* Returns true for every token, including EOF, and false after a lexing error. */
bool pbnfc_grammar_lexer_next(PbnfcGrammarLexer *lexer,
                               PbnfcGrammarToken *token);

bool pbnfc_grammar_lexer_failed(const PbnfcGrammarLexer *lexer);

const char *pbnfc_grammar_token_kind_name(PbnfcGrammarTokenKind kind);

#endif
