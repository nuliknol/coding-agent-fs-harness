#include "grammar_ast.h"

#include "grammar_lexer.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    PbnfcGrammarLexer lexer;
    const PbnfcDiagnosticContext *diagnostics;
    PbnfcGrammarToken current;
    bool have_current;
    bool failed;
} GrammarParser;

static bool size_add_ok(size_t left, size_t right, size_t *result)
{
    if (right > SIZE_MAX - left) {
        return false;
    }
    *result = left + right;
    return true;
}

static bool size_mul_ok(size_t left, size_t right, size_t *result)
{
    if (left != 0U && right > SIZE_MAX / left) {
        return false;
    }
    *result = left * right;
    return true;
}

static void free_symbol(PbnfcGrammarSymbol *symbol)
{
    if (symbol != NULL) {
        free(symbol->name);
        symbol->name = NULL;
    }
}

static void free_alternative(PbnfcGrammarAlternative *alternative)
{
    size_t index;

    if (alternative == NULL) {
        return;
    }
    for (index = 0U; index < alternative->symbol_count; ++index) {
        free_symbol(&alternative->symbols[index]);
    }
    free(alternative->symbols);
    alternative->symbols = NULL;
    alternative->symbol_count = 0U;
}

static void free_production(PbnfcGrammarProduction *production)
{
    size_t index;

    if (production == NULL) {
        return;
    }
    free(production->name);
    production->name = NULL;
    for (index = 0U; index < production->alternative_count; ++index) {
        free_alternative(&production->alternatives[index]);
    }
    free(production->alternatives);
    production->alternatives = NULL;
    production->alternative_count = 0U;
}

void pbnfc_grammar_free(PbnfcGrammar *grammar)
{
    size_t index;

    if (grammar == NULL) {
        return;
    }
    for (index = 0U; index < grammar->start_count; ++index) {
        free(grammar->starts[index].name);
    }
    free(grammar->starts);
    for (index = 0U; index < grammar->token_declaration_count; ++index) {
        free(grammar->token_declarations[index].name);
    }
    free(grammar->token_declarations);
    for (index = 0U; index < grammar->production_count; ++index) {
        free_production(&grammar->productions[index]);
    }
    free(grammar->productions);
    free(grammar);
}

static char *copy_bytes(const char *text, size_t length)
{
    size_t allocation_size;
    char *copy;

    if (!size_add_ok(length, 1U, &allocation_size)) {
        return NULL;
    }
    copy = (char *)malloc(allocation_size);
    if (copy == NULL) {
        return NULL;
    }
    if (length != 0U) {
        (void)memcpy(copy, text, length);
    }
    copy[length] = '\0';
    return copy;
}

static char *copy_terminal(const PbnfcGrammarToken *token)
{
    size_t source_index;
    size_t value_length = 0U;
    char *value;
    size_t value_index = 0U;

    /* The lexer guarantees a quoted terminal with valid escape pairs. */
    for (source_index = 1U; source_index + 1U < token->length;
         ++source_index) {
        if (token->text[source_index] == '\\') {
            ++source_index;
        }
        ++value_length;
    }
    value = (char *)malloc(value_length + 1U);
    if (value == NULL) {
        return NULL;
    }
    for (source_index = 1U; source_index + 1U < token->length;
         ++source_index) {
        char character = token->text[source_index];

        if (character == '\\') {
            ++source_index;
            character = token->text[source_index];
        }
        value[value_index] = character;
        ++value_index;
    }
    value[value_index] = '\0';
    return value;
}

static bool parser_error(GrammarParser *parser,
                         const PbnfcLocation *location,
                         const char *detail)
{
    parser->failed = true;
    if (parser->diagnostics != NULL) {
        (void)pbnfc_diagnostic_emit(parser->diagnostics, detail, location);
    }
    return false;
}

static bool parser_advance(GrammarParser *parser)
{
    if (!pbnfc_grammar_lexer_next(&parser->lexer, &parser->current)) {
        parser->failed = true;
        return false;
    }
    parser->have_current = true;
    return true;
}

static bool parser_expect(GrammarParser *parser,
                          PbnfcGrammarTokenKind kind,
                          const char *detail)
{
    if (!parser->have_current && !parser_advance(parser)) {
        return false;
    }
    if (parser->current.kind != kind) {
        return parser_error(parser, &parser->current.location, detail);
    }
    return true;
}

static bool append_start(PbnfcGrammar *grammar,
                         const PbnfcGrammarToken *token)
{
    size_t count;
    size_t bytes;
    PbnfcGrammarStartDirective *starts;
    char *name;

    if (!size_add_ok(grammar->start_count, 1U, &count) ||
        !size_mul_ok(count, sizeof(*starts), &bytes)) {
        return false;
    }
    name = copy_bytes(token->text, token->length);
    if (name == NULL) {
        return false;
    }
    starts = (PbnfcGrammarStartDirective *)realloc(grammar->starts, bytes);
    if (starts == NULL) {
        free(name);
        return false;
    }
    grammar->starts = starts;
    grammar->starts[grammar->start_count].name = name;
    grammar->starts[grammar->start_count].location = token->location;
    ++grammar->start_count;
    if (grammar->start_count == 1U) {
        grammar->start_name = grammar->starts[0].name;
    }
    return true;
}

static bool append_token_declaration(PbnfcGrammar *grammar,
                                     const PbnfcGrammarToken *token)
{
    size_t count;
    size_t bytes;
    PbnfcGrammarTokenDeclaration *declarations;
    char *name;

    if (!size_add_ok(grammar->token_declaration_count, 1U, &count) ||
        !size_mul_ok(count, sizeof(*declarations), &bytes)) {
        return false;
    }
    name = copy_bytes(token->text, token->length);
    if (name == NULL) {
        return false;
    }
    declarations = (PbnfcGrammarTokenDeclaration *)realloc(
        grammar->token_declarations, bytes);
    if (declarations == NULL) {
        free(name);
        return false;
    }
    grammar->token_declarations = declarations;
    grammar->token_declarations[grammar->token_declaration_count].name = name;
    grammar->token_declarations[grammar->token_declaration_count].location =
        token->location;
    ++grammar->token_declaration_count;
    return true;
}

static bool append_production(PbnfcGrammar *grammar,
                              const PbnfcGrammarToken *token,
                              PbnfcGrammarProduction **production)
{
    size_t count;
    size_t bytes;
    PbnfcGrammarProduction *productions;
    char *name;

    if (!size_add_ok(grammar->production_count, 1U, &count) ||
        !size_mul_ok(count, sizeof(*productions), &bytes)) {
        return false;
    }
    name = copy_bytes(token->text, token->length);
    if (name == NULL) {
        return false;
    }
    productions = (PbnfcGrammarProduction *)realloc(grammar->productions,
                                                     bytes);
    if (productions == NULL) {
        free(name);
        return false;
    }
    grammar->productions = productions;
    grammar->productions[grammar->production_count].name = name;
    grammar->productions[grammar->production_count].location = token->location;
    grammar->productions[grammar->production_count].alternatives = NULL;
    grammar->productions[grammar->production_count].alternative_count = 0U;
    *production = &grammar->productions[grammar->production_count];
    ++grammar->production_count;
    return true;
}

static bool append_alternative(PbnfcGrammarProduction *production,
                               PbnfcGrammarAlternative **alternative)
{
    size_t count;
    size_t bytes;
    PbnfcGrammarAlternative *alternatives;

    if (!size_add_ok(production->alternative_count, 1U, &count) ||
        !size_mul_ok(count, sizeof(*alternatives), &bytes)) {
        return false;
    }
    alternatives = (PbnfcGrammarAlternative *)realloc(
        production->alternatives, bytes);
    if (alternatives == NULL) {
        return false;
    }
    production->alternatives = alternatives;
    alternatives[production->alternative_count].symbols = NULL;
    alternatives[production->alternative_count].symbol_count = 0U;
    *alternative = &alternatives[production->alternative_count];
    ++production->alternative_count;
    return true;
}

static bool append_symbol(PbnfcGrammarAlternative *alternative,
                          const PbnfcGrammarToken *token)
{
    size_t count;
    size_t bytes;
    PbnfcGrammarSymbol *symbols;
    char *name;
    PbnfcGrammarSymbolKind kind;

    if (!size_add_ok(alternative->symbol_count, 1U, &count) ||
        !size_mul_ok(count, sizeof(*symbols), &bytes)) {
        return false;
    }
    if (token->kind == PBNFC_GRAMMAR_TOKEN_TERMINAL) {
        name = copy_terminal(token);
        kind = PBNFC_GRAMMAR_SYMBOL_TERMINAL;
    } else if (token->kind == PBNFC_GRAMMAR_TOKEN_REFERENCE) {
        name = copy_bytes(token->text + 1U, token->length - 1U);
        kind = PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE;
    } else {
        name = copy_bytes(token->text, token->length);
        kind = PBNFC_GRAMMAR_SYMBOL_NONTERMINAL;
    }
    if (name == NULL) {
        return false;
    }
    symbols = (PbnfcGrammarSymbol *)realloc(alternative->symbols, bytes);
    if (symbols == NULL) {
        free(name);
        return false;
    }
    alternative->symbols = symbols;
    symbols[alternative->symbol_count].kind = kind;
    symbols[alternative->symbol_count].name = name;
    symbols[alternative->symbol_count].location = token->location;
    ++alternative->symbol_count;
    return true;
}

static bool parse_start(GrammarParser *parser, PbnfcGrammar *grammar)
{
    if (!parser_advance(parser) ||
        !parser_expect(parser,
                       PBNFC_GRAMMAR_TOKEN_IDENTIFIER,
                       "expected start rule name")) {
        return false;
    }
    if (!append_start(grammar, &parser->current)) {
        return parser_error(parser, &parser->current.location,
                            "grammar AST allocation failed");
    }
    return parser_advance(parser);
}

static bool parse_token_declaration(GrammarParser *parser,
                                    PbnfcGrammar *grammar)
{
    if (!parser_advance(parser) ||
        !parser_expect(parser,
                       PBNFC_GRAMMAR_TOKEN_IDENTIFIER,
                       "expected token declaration name")) {
        return false;
    }
    if (!append_token_declaration(grammar, &parser->current)) {
        return parser_error(parser, &parser->current.location,
                            "grammar AST allocation failed");
    }
    return parser_advance(parser);
}

static bool is_symbol_token(PbnfcGrammarTokenKind kind)
{
    return kind == PBNFC_GRAMMAR_TOKEN_IDENTIFIER ||
           kind == PBNFC_GRAMMAR_TOKEN_TERMINAL ||
           kind == PBNFC_GRAMMAR_TOKEN_REFERENCE;
}

static bool parse_production(GrammarParser *parser,
                             PbnfcGrammar *grammar)
{
    PbnfcGrammarProduction *production;
    PbnfcGrammarAlternative *alternative;

    if (!append_production(grammar, &parser->current, &production)) {
        return parser_error(parser, &parser->current.location,
                            "grammar AST allocation failed");
    }
    if (!parser_advance(parser) ||
        !parser_expect(parser,
                       PBNFC_GRAMMAR_TOKEN_ASSIGN,
                       "expected ::= after production name")) {
        return false;
    }
    if (!parser_advance(parser)) {
        return false;
    }

    for (;;) {
        if (!append_alternative(production, &alternative)) {
            return parser_error(parser, &parser->current.location,
                                "grammar AST allocation failed");
        }
        while (is_symbol_token(parser->current.kind)) {
            if (!append_symbol(alternative, &parser->current)) {
                return parser_error(parser, &parser->current.location,
                                    "grammar AST allocation failed");
            }
            if (!parser_advance(parser)) {
                return false;
            }
        }
        if (parser->current.kind == PBNFC_GRAMMAR_TOKEN_SEMICOLON) {
            return parser_advance(parser);
        }
        if (parser->current.kind != PBNFC_GRAMMAR_TOKEN_PIPE) {
            return parser_error(parser, &parser->current.location,
                                "expected | or ; after production alternative");
        }
        if (!parser_advance(parser)) {
            return false;
        }
    }
}

static bool parse_source(GrammarParser *parser, PbnfcGrammar *grammar)
{
    bool saw_production = false;

    if (!parser_advance(parser)) {
        return false;
    }
    while (parser->current.kind != PBNFC_GRAMMAR_TOKEN_EOF) {
        if (parser->current.kind == PBNFC_GRAMMAR_TOKEN_START_DIRECTIVE) {
            if (saw_production) {
                return parser_error(parser, &parser->current.location,
                                    "directives must precede productions");
            }
            if (!parse_start(parser, grammar)) {
                return false;
            }
        } else if (parser->current.kind == PBNFC_GRAMMAR_TOKEN_TOKEN_DIRECTIVE) {
            if (saw_production) {
                return parser_error(parser, &parser->current.location,
                                    "directives must precede productions");
            }
            if (!parse_token_declaration(parser, grammar)) {
                return false;
            }
        } else if (parser->current.kind == PBNFC_GRAMMAR_TOKEN_IDENTIFIER) {
            saw_production = true;
            if (!parse_production(parser, grammar)) {
                return false;
            }
        } else {
            return parser_error(parser, &parser->current.location,
                                "expected grammar directive or production");
        }
    }
    return true;
}

bool pbnfc_grammar_parse(const char *source,
                         size_t length,
                         const PbnfcDiagnosticContext *diagnostics,
                         PbnfcGrammar **grammar_out)
{
    GrammarParser parser;
    PbnfcGrammar *grammar;

    if (grammar_out == NULL) {
        return false;
    }
    *grammar_out = NULL;
    grammar = (PbnfcGrammar *)calloc(1U, sizeof(*grammar));
    if (grammar == NULL) {
        if (diagnostics != NULL) {
            (void)pbnfc_diagnostic_emit(diagnostics,
                                        "grammar AST allocation failed",
                                        NULL);
        }
        return false;
    }
    (void)memset(&parser, 0, sizeof(parser));
    parser.diagnostics = diagnostics;
    pbnfc_grammar_lexer_init(&parser.lexer, source, length, diagnostics);
    if (!parse_source(&parser, grammar) || parser.failed) {
        pbnfc_grammar_free(grammar);
        return false;
    }
    *grammar_out = grammar;
    return true;
}
