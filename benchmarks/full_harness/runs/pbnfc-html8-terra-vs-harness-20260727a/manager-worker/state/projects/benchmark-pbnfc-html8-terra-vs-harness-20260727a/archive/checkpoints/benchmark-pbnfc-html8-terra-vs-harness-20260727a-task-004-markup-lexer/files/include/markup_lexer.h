#ifndef PBNFC_MARKUP_LEXER_H
#define PBNFC_MARKUP_LEXER_H

#include "diagnostics.h"

#include <stdbool.h>
#include <stddef.h>

typedef enum {
    PBNFC_MARKUP_TOKEN_EOF = 0,
    PBNFC_MARKUP_TOKEN_LESS_THAN,
    PBNFC_MARKUP_TOKEN_GREATER_THAN,
    PBNFC_MARKUP_TOKEN_SLASH,
    PBNFC_MARKUP_TOKEN_EQUALS,
    PBNFC_MARKUP_TOKEN_IDENT,

    /* Short names keep punctuation tokens convenient for scanner clients. */
    PBNFC_MARKUP_TOKEN_LT = PBNFC_MARKUP_TOKEN_LESS_THAN,
    PBNFC_MARKUP_TOKEN_GT = PBNFC_MARKUP_TOKEN_GREATER_THAN,
    PBNFC_MARKUP_TOKEN_EQUAL = PBNFC_MARKUP_TOKEN_EQUALS,
    PBNFC_MARKUP_TOKEN_IDENTIFIER = PBNFC_MARKUP_TOKEN_IDENT
} PbnfcMarkupTokenKind;

/* A token is a non-owning view into the source supplied to the lexer. */
typedef struct {
    PbnfcMarkupTokenKind kind;
    PbnfcLocation location;
    const char *text;
    size_t length;
} PbnfcMarkupToken;

typedef struct {
    const char *source;
    size_t length;
    size_t offset;
    size_t line;
    size_t column;
    bool in_tag;
    bool failed;
} PbnfcMarkupLexer;

/* Initialize a core tag scanner. The source buffer remains caller-owned. */
void pbnfc_markup_lexer_init(PbnfcMarkupLexer *lexer,
                             const char *source,
                             size_t length);

/* Returns true for each token, including EOF, and false after malformed input. */
bool pbnfc_markup_lexer_next(PbnfcMarkupLexer *lexer,
                             PbnfcMarkupToken *token);

bool pbnfc_markup_lexer_failed(const PbnfcMarkupLexer *lexer);

const char *pbnfc_markup_token_kind_name(PbnfcMarkupTokenKind kind);

#endif
