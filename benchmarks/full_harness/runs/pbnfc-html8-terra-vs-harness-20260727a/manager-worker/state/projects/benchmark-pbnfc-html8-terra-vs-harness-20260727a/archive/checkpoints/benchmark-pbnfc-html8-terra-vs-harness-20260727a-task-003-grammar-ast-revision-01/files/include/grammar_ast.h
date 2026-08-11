#ifndef PBNFC_GRAMMAR_AST_H
#define PBNFC_GRAMMAR_AST_H

#include "diagnostics.h"

#include <stdbool.h>
#include <stddef.h>

typedef enum {
    PBNFC_GRAMMAR_SYMBOL_TERMINAL = 0,
    PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE,
    PBNFC_GRAMMAR_SYMBOL_NONTERMINAL
} PbnfcGrammarSymbolKind;

typedef struct {
    PbnfcGrammarSymbolKind kind;
    char *name;
    PbnfcLocation location;
} PbnfcGrammarSymbol;

typedef struct {
    PbnfcGrammarSymbol *symbols;
    size_t symbol_count;
} PbnfcGrammarAlternative;

typedef struct {
    char *name;
    PbnfcLocation location;
    PbnfcGrammarAlternative *alternatives;
    size_t alternative_count;
} PbnfcGrammarProduction;

typedef struct {
    char *name;
    PbnfcLocation location;
} PbnfcGrammarTokenDeclaration;

typedef struct {
    char *name;
    PbnfcLocation location;
} PbnfcGrammarStartDirective;

typedef struct {
    PbnfcGrammarStartDirective *starts;
    size_t start_count;

    /* This aliases starts[0].name when start_count is nonzero. */
    const char *start_name;

    PbnfcGrammarTokenDeclaration *token_declarations;
    size_t token_declaration_count;
    PbnfcGrammarProduction *productions;
    size_t production_count;
} PbnfcGrammar;

/*
 * Parse grammar source into an independently owned AST. The source buffer is
 * only borrowed while parsing; all names and terminal values in the result
 * are copied. Terminal names are unquoted and have \' and \\ decoded, while
 * token-reference names do not include their leading '$'.
 */
bool pbnfc_grammar_parse(const char *source,
                         size_t length,
                         const PbnfcDiagnosticContext *diagnostics,
                         PbnfcGrammar **grammar_out);

/* Validate declarations and references without taking ownership of grammar. */
bool pbnfc_grammar_validate(const PbnfcGrammar *grammar,
                            const PbnfcDiagnosticContext *diagnostics);

void pbnfc_grammar_free(PbnfcGrammar *grammar);

#endif
