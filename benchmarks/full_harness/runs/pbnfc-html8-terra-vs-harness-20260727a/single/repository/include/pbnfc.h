#ifndef PBNFC_H
#define PBNFC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct { size_t offset, line, column; } Location;
typedef struct { char *text; int kind; Location loc; } MarkToken;
typedef struct { MarkToken *v; size_t n, cap; Location end; } MarkTokens;

enum { MK_IDENT = 1, MK_STRING, MK_TEXT, MK_LITERAL };
typedef enum { SYM_NONTERM, SYM_KIND, SYM_LITERAL } SymType;
typedef struct { SymType type; int value; char *literal; } Symbol;
typedef struct { int lhs; Symbol *rhs; size_t nrhs; } Rule;
typedef struct {
    char **names; size_t nnames, names_cap;
    char **kinds; size_t nkinds, kinds_cap;
    Rule *rules; size_t nrules, rules_cap;
    int start;
} Grammar;

typedef struct { char message[512]; Location loc; } Error;

void grammar_init(Grammar *g);
void grammar_free(Grammar *g);
bool grammar_load(const char *path, Grammar *g, Error *err);
bool markup_load(const char *path, MarkTokens *out, Error *err);
void tokens_free(MarkTokens *t);

typedef struct Pool Pool;
Pool *pool_create(Error *err);
void pool_destroy(Pool *p);
bool recognize(Pool *p, const Grammar *g, const MarkTokens *tokens,
               bool *accepted, size_t *rounds, size_t tasks[8],
               size_t *reject_at, char *expected, size_t expected_size, Error *err);

void error_set(Error *e, Location loc, const char *fmt, ...);
#endif
