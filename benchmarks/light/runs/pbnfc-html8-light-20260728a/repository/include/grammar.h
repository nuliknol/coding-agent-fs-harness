#ifndef PBNFC_GRAMMAR_H
#define PBNFC_GRAMMAR_H

#include <stddef.h>
#include "diagnostics.h"

typedef enum { SYM_NONTERM, SYM_LITERAL, SYM_TOKEN } SymbolKind;
typedef enum { TOK_IDENT, TOK_STRING, TOK_TEXT } GrammarTokenKind;

typedef struct {
    SymbolKind kind;
    char *text;
    GrammarTokenKind token_kind;
} GrammarSymbol;

typedef struct {
    GrammarSymbol *symbols;
    size_t count;
    size_t capacity;
} Alternative;

typedef struct {
    char *name;
    Alternative *alternatives;
    size_t count;
    size_t capacity;
} Rule;

typedef struct {
    char *start_name;
    size_t start_rule;
    int declared_tokens[3];
    Rule *rules;
    size_t rule_count;
    size_t rule_capacity;
} Grammar;

int grammar_parse(const char *source, size_t length, Grammar *grammar, Diagnostic *diagnostic);
int grammar_set_start(Grammar *grammar, const char *name, Diagnostic *diagnostic);
void grammar_free(Grammar *grammar);

#endif
