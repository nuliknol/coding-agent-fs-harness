#ifndef BNFC_LEXER_H
#define BNFC_LEXER_H

#include <stddef.h>

typedef enum {
    GRAMMAR_TOKEN_START,
    GRAMMAR_TOKEN_IDENTIFIER,
    GRAMMAR_TOKEN_DEFINE,
    GRAMMAR_TOKEN_PIPE,
    GRAMMAR_TOKEN_SEMICOLON,
    GRAMMAR_TOKEN_TERMINAL,
    GRAMMAR_TOKEN_EOF
} GrammarTokenType;

typedef struct {
    GrammarTokenType type;
    char *value;
    size_t line;
} GrammarToken;

typedef struct {
    GrammarToken *items;
    size_t count;
} GrammarTokenList;

/* Returns 0 on success and -1 on an I/O or grammar-lexing error. */
int grammar_lex_file(const char *path, GrammarTokenList *tokens,
                     char *error, size_t error_size);

void grammar_token_list_destroy(GrammarTokenList *tokens);

#endif
