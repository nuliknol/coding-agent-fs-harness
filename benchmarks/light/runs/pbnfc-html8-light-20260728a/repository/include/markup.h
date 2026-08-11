#ifndef PBNFC_MARKUP_H
#define PBNFC_MARKUP_H

#include <stddef.h>
#include "diagnostics.h"

typedef enum { MARKUP_IDENT, MARKUP_STRING, MARKUP_TEXT, MARKUP_LITERAL } MarkupKind;

typedef struct {
    MarkupKind kind;
    char *lexeme;
    Location loc;
} MarkupToken;

typedef struct {
    MarkupToken *tokens;
    size_t count;
    size_t capacity;
} Markup;

int markup_lex(const char *source, size_t length, Markup *markup, Diagnostic *diagnostic);
void markup_free(Markup *markup);

#endif
