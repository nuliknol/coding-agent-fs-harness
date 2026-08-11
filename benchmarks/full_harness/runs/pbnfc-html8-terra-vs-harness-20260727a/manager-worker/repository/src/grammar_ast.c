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

static bool names_equal(const char *left, const char *right)
{
    return left != NULL && right != NULL && strcmp(left, right) == 0;
}

static const PbnfcLocation *earliest_location(const PbnfcGrammar *grammar)
{
    const PbnfcLocation *result = NULL;
    size_t index;

    for (index = 0U; index < grammar->start_count; ++index) {
        if (result == NULL ||
            grammar->starts[index].location.byte_offset <
                result->byte_offset) {
            result = &grammar->starts[index].location;
        }
    }
    for (index = 0U; index < grammar->token_declaration_count; ++index) {
        if (result == NULL ||
            grammar->token_declarations[index].location.byte_offset <
                result->byte_offset) {
            result = &grammar->token_declarations[index].location;
        }
    }
    for (index = 0U; index < grammar->production_count; ++index) {
        if (result == NULL ||
            grammar->productions[index].location.byte_offset <
                result->byte_offset) {
            result = &grammar->productions[index].location;
        }
    }
    return result;
}

static bool validation_error(const PbnfcDiagnosticContext *diagnostics,
                             const PbnfcLocation *location,
                             const char *detail)
{
    if (diagnostics != NULL) {
        (void)pbnfc_diagnostic_emit(diagnostics, detail, location);
    }
    return false;
}

static bool token_name_is_declared(const PbnfcGrammar *grammar,
                                   const char *name)
{
    size_t index;

    for (index = 0U; index < grammar->token_declaration_count; ++index) {
        if (names_equal(grammar->token_declarations[index].name, name)) {
            return true;
        }
    }
    return false;
}

static bool production_name_is_defined(const PbnfcGrammar *grammar,
                                       const char *name)
{
    size_t index;

    for (index = 0U; index < grammar->production_count; ++index) {
        if (names_equal(grammar->productions[index].name, name)) {
            return true;
        }
    }
    return false;
}

static bool production_index(const PbnfcGrammar *grammar,
                             const char *name,
                             size_t *index_out)
{
    size_t index;

    for (index = 0U; index < grammar->production_count; ++index) {
        if (names_equal(grammar->productions[index].name, name)) {
            if (index_out != NULL) {
                *index_out = index;
            }
            return true;
        }
    }
    return false;
}

static void compute_nullable_productions(const PbnfcGrammar *grammar,
                                         bool *nullable)
{
    bool changed;
    size_t production_index_value;

    do {
        changed = false;
        for (production_index_value = 0U;
             production_index_value < grammar->production_count;
             ++production_index_value) {
            const PbnfcGrammarProduction *production =
                &grammar->productions[production_index_value];
            size_t alternative_index;

            if (nullable[production_index_value]) {
                continue;
            }
            for (alternative_index = 0U;
                 alternative_index < production->alternative_count;
                 ++alternative_index) {
                const PbnfcGrammarAlternative *alternative =
                    &production->alternatives[alternative_index];
                bool alternative_nullable = true;
                size_t symbol_index;

                for (symbol_index = 0U;
                     symbol_index < alternative->symbol_count;
                     ++symbol_index) {
                    const PbnfcGrammarSymbol *symbol =
                        &alternative->symbols[symbol_index];
                    size_t referenced_index;

                    if (symbol->kind !=
                            PBNFC_GRAMMAR_SYMBOL_NONTERMINAL ||
                        !production_index(grammar,
                                          symbol->name,
                                          &referenced_index) ||
                        !nullable[referenced_index]) {
                        alternative_nullable = false;
                        break;
                    }
                }
                if (alternative_nullable) {
                    nullable[production_index_value] = true;
                    changed = true;
                    break;
                }
            }
        }
    } while (changed);
}

static bool find_left_recursion_from(const PbnfcGrammar *grammar,
                                     const bool *nullable,
                                     size_t origin,
                                     bool *visited,
                                     size_t *stack,
                                     const PbnfcLocation **location_out)
{
    size_t top = 0U;

    (void)memset(visited, 0, grammar->production_count * sizeof(*visited));
    visited[origin] = true;
    stack[top] = origin;
    ++top;

    while (top != 0U) {
        size_t source_index = stack[--top];
        const PbnfcGrammarProduction *production =
            &grammar->productions[source_index];
        size_t alternative_index;

        for (alternative_index = 0U;
             alternative_index < production->alternative_count;
             ++alternative_index) {
            const PbnfcGrammarAlternative *alternative =
                &production->alternatives[alternative_index];
            size_t symbol_index;

            for (symbol_index = 0U;
                 symbol_index < alternative->symbol_count;
                 ++symbol_index) {
                const PbnfcGrammarSymbol *symbol =
                    &alternative->symbols[symbol_index];
                size_t target_index;

                if (symbol->kind != PBNFC_GRAMMAR_SYMBOL_NONTERMINAL) {
                    break;
                }
                if (!production_index(grammar,
                                      symbol->name,
                                      &target_index)) {
                    break;
                }
                if (target_index == origin) {
                    if (location_out != NULL) {
                        *location_out = &symbol->location;
                    }
                    return true;
                }
                if (!visited[target_index]) {
                    visited[target_index] = true;
                    stack[top] = target_index;
                    ++top;
                }
                if (!nullable[target_index]) {
                    break;
                }
            }
        }
    }
    return false;
}

static bool validate_left_recursion(const PbnfcGrammar *grammar,
                                    const PbnfcDiagnosticContext *diagnostics)
{
    bool *nullable;
    bool *visited;
    size_t *stack;
    size_t nullable_bytes;
    size_t visited_bytes;
    size_t stack_bytes;
    size_t index;

    if (!size_mul_ok(grammar->production_count,
                     sizeof(*nullable),
                     &nullable_bytes)) {
        return validation_error(diagnostics,
                                earliest_location(grammar),
                                "grammar validation allocation failed");
    }
    nullable = (bool *)calloc(1U, nullable_bytes);
    if (nullable == NULL) {
        return validation_error(diagnostics,
                                earliest_location(grammar),
                                "grammar validation allocation failed");
    }
    if (!size_mul_ok(grammar->production_count,
                     sizeof(*stack),
                     &stack_bytes)) {
        free(nullable);
        return validation_error(diagnostics,
                                earliest_location(grammar),
                                "grammar validation allocation failed");
    }
    if (!size_mul_ok(grammar->production_count,
                     sizeof(*visited),
                     &visited_bytes)) {
        free(nullable);
        return validation_error(diagnostics,
                                earliest_location(grammar),
                                "grammar validation allocation failed");
    }
    visited = (bool *)calloc(1U, visited_bytes);
    stack = (size_t *)malloc(stack_bytes);
    if (visited == NULL || stack == NULL) {
        free(visited);
        free(stack);
        free(nullable);
        return validation_error(diagnostics,
                                earliest_location(grammar),
                                "grammar validation allocation failed");
    }

    compute_nullable_productions(grammar, nullable);
    for (index = 0U; index < grammar->production_count; ++index) {
        const PbnfcLocation *location = NULL;

        if (find_left_recursion_from(grammar,
                                     nullable,
                                     index,
                                     visited,
                                     stack,
                                     &location)) {
            free(visited);
            free(stack);
            free(nullable);
            return validation_error(diagnostics,
                                    location,
                                    "left recursion detected");
        }
    }
    free(visited);
    free(stack);
    free(nullable);
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

bool pbnfc_grammar_validate(const PbnfcGrammar *grammar,
                            const PbnfcDiagnosticContext *diagnostics)
{
    size_t index;
    size_t nested_index;
    const PbnfcLocation *location;

    if (grammar == NULL) {
        return validation_error(diagnostics, NULL, "grammar is unavailable");
    }

    if (grammar->start_count == 0U) {
        location = earliest_location(grammar);
        return validation_error(diagnostics,
                                location,
                                "grammar requires exactly one %start declaration");
    }
    if (grammar->start_count != 1U) {
        return validation_error(
            diagnostics,
            &grammar->starts[1].location,
            "grammar requires exactly one %start declaration");
    }
    for (index = 0U; index < grammar->token_declaration_count; ++index) {
        if (grammar->token_declarations[index].location.byte_offset <
            grammar->starts[0].location.byte_offset) {
            return validation_error(
                diagnostics,
                &grammar->starts[0].location,
                "the %start declaration must be the first directive");
        }
    }

    for (index = 0U; index < grammar->token_declaration_count; ++index) {
        for (nested_index = 0U; nested_index < index; ++nested_index) {
            if (names_equal(grammar->token_declarations[index].name,
                            grammar->token_declarations[nested_index].name)) {
                return validation_error(
                    diagnostics,
                    &grammar->token_declarations[index].location,
                    "duplicate token declaration");
            }
        }
    }

    for (index = 0U; index < grammar->production_count; ++index) {
        for (nested_index = 0U; nested_index < index; ++nested_index) {
            if (names_equal(grammar->productions[index].name,
                            grammar->productions[nested_index].name)) {
                return validation_error(diagnostics,
                                        &grammar->productions[index].location,
                                        "duplicate rule definition");
            }
        }
    }

    if (!production_name_is_defined(grammar, grammar->starts[0].name)) {
        return validation_error(diagnostics,
                                &grammar->starts[0].location,
                                "start rule is undefined");
    }

    for (index = 0U; index < grammar->production_count; ++index) {
        const PbnfcGrammarProduction *production = &grammar->productions[index];

        for (nested_index = 0U;
             nested_index < production->alternative_count;
             ++nested_index) {
            const PbnfcGrammarAlternative *alternative =
                &production->alternatives[nested_index];
            size_t symbol_index;

            for (symbol_index = 0U;
                 symbol_index < alternative->symbol_count;
                 ++symbol_index) {
                const PbnfcGrammarSymbol *symbol =
                    &alternative->symbols[symbol_index];

                if (symbol->kind == PBNFC_GRAMMAR_SYMBOL_NONTERMINAL &&
                    !production_name_is_defined(grammar, symbol->name)) {
                    return validation_error(
                        diagnostics,
                        &symbol->location,
                        "undefined nonterminal reference");
                }
                if (symbol->kind == PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE &&
                    !token_name_is_declared(grammar, symbol->name)) {
                    return validation_error(diagnostics,
                                            &symbol->location,
                                            "undefined token reference");
                }
            }
        }
    }
    return validate_left_recursion(grammar, diagnostics);
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
