#include "grammar.h"

#include <stdlib.h>
#include <string.h>

typedef enum { G_EOF, G_IDENT, G_STRING, G_PERCENT, G_ASSIGN, G_PIPE, G_SEMI,
               G_DOLLAR, G_BAD } GTokenKind;

typedef struct {
    GTokenKind kind;
    char *text;
    Location loc;
} GrammarToken;

typedef struct {
    const char *source;
    size_t length;
    size_t pos;
    Location loc;
    Diagnostic *diagnostic;
} GrammarLexer;

typedef struct {
    GrammarLexer lexer;
    GrammarToken current;
    Grammar *grammar;
    Diagnostic *diagnostic;
} GrammarParser;

static char *copy_text(const char *text, size_t length)
{
    char *result = (char *)malloc(length + 1);
    if (result != NULL) {
        memcpy(result, text, length);
        result[length] = '\0';
    }
    return result;
}

static void grammar_token_free(GrammarToken *token)
{
    free(token->text);
    token->text = NULL;
}

static void advance_location(GrammarLexer *lexer, char c)
{
    lexer->pos++;
    if (c == '\n') {
        lexer->loc.line++;
        lexer->loc.column = 1;
    } else {
        lexer->loc.column++;
    }
}

static void lex_error(GrammarLexer *lexer, Location loc, const char *message)
{
    if (!lexer->diagnostic->present)
        diagnostic_set(lexer->diagnostic, loc, message);
}

static GrammarToken grammar_next(GrammarLexer *lexer)
{
    GrammarToken token;
    size_t start;
    size_t out;
    token.kind = G_EOF;
    token.text = NULL;
    token.loc = lexer->loc;
    while (lexer->pos < lexer->length) {
        char c = lexer->source[lexer->pos];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            advance_location(lexer, c);
        } else if (c == '#') {
            while (lexer->pos < lexer->length && lexer->source[lexer->pos] != '\n')
                advance_location(lexer, lexer->source[lexer->pos]);
        } else {
            break;
        }
    }
    token.loc = lexer->loc;
    if (lexer->pos == lexer->length)
        return token;
    start = lexer->pos;
    if ((lexer->source[lexer->pos] >= 'A' && lexer->source[lexer->pos] <= 'Z') ||
        (lexer->source[lexer->pos] >= 'a' && lexer->source[lexer->pos] <= 'z') ||
        lexer->source[lexer->pos] == '_') {
        advance_location(lexer, lexer->source[lexer->pos]);
        while (lexer->pos < lexer->length) {
            char c = lexer->source[lexer->pos];
            if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') || c == '_'))
                break;
            advance_location(lexer, c);
        }
        token.kind = G_IDENT;
        token.text = copy_text(lexer->source + start, lexer->pos - start);
        if (token.text == NULL)
            lex_error(lexer, token.loc, "out of memory");
        return token;
    }
    if (lexer->source[lexer->pos] == '%') {
        advance_location(lexer, '%');
        start = lexer->pos;
        while (lexer->pos < lexer->length) {
            char c = lexer->source[lexer->pos];
            if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'))
                break;
            advance_location(lexer, c);
        }
        if (start == lexer->pos) {
            lex_error(lexer, token.loc, "expected directive name");
            token.kind = G_BAD;
            return token;
        }
        token.kind = G_PERCENT;
        token.text = copy_text(lexer->source + start, lexer->pos - start);
        if (token.text == NULL)
            lex_error(lexer, token.loc, "out of memory");
        return token;
    }
    if (lexer->source[lexer->pos] == '\'') {
        advance_location(lexer, '\'');
        out = 0;
        token.text = (char *)malloc(1);
        if (token.text == NULL) {
            lex_error(lexer, token.loc, "out of memory");
            token.kind = G_BAD;
            return token;
        }
        token.text[0] = '\0';
        while (lexer->pos < lexer->length && lexer->source[lexer->pos] != '\'') {
            char c = lexer->source[lexer->pos];
            if (c == '\\') {
                advance_location(lexer, c);
                if (lexer->pos == lexer->length ||
                    (lexer->source[lexer->pos] != '\'' && lexer->source[lexer->pos] != '\\')) {
                    lex_error(lexer, lexer->loc, "unsupported string escape");
                    grammar_token_free(&token);
                    token.kind = G_BAD;
                    return token;
                }
                c = lexer->source[lexer->pos];
            }
            {
                char *grown = (char *)realloc(token.text, out + 2);
                if (grown == NULL) {
                    lex_error(lexer, token.loc, "out of memory");
                    grammar_token_free(&token);
                    token.kind = G_BAD;
                    return token;
                }
                token.text = grown;
            }
            token.text[out++] = c;
            token.text[out] = '\0';
            advance_location(lexer, c);
        }
        if (lexer->pos == lexer->length) {
            lex_error(lexer, token.loc, "unterminated grammar string");
            grammar_token_free(&token);
            token.kind = G_BAD;
            return token;
        }
        advance_location(lexer, '\'');
        token.kind = G_STRING;
        return token;
    }
    advance_location(lexer, lexer->source[lexer->pos]);
    switch (lexer->source[start]) {
    case ':':
        if (lexer->pos + 1 < lexer->length && lexer->source[lexer->pos] == ':' &&
            lexer->source[lexer->pos + 1] == '=') {
            advance_location(lexer, ':');
            advance_location(lexer, '=');
            token.kind = G_ASSIGN;
        } else {
            token.kind = G_BAD;
            lex_error(lexer, token.loc, "expected ::= operator");
        }
        break;
    case '|': token.kind = G_PIPE; break;
    case ';': token.kind = G_SEMI; break;
    case '$': token.kind = G_DOLLAR; break;
    default:
        token.kind = G_BAD;
        lex_error(lexer, token.loc, "invalid grammar character");
        break;
    }
    return token;
}

static int parser_advance(GrammarParser *parser)
{
    grammar_token_free(&parser->current);
    parser->current = grammar_next(&parser->lexer);
    return parser->diagnostic->present ? -1 : 0;
}

static void parse_error(GrammarParser *parser, const char *message)
{
    if (!parser->diagnostic->present)
        diagnostic_set(parser->diagnostic, parser->current.loc, message);
}

static int grow_array(void **data, size_t *capacity, size_t item_size, size_t needed)
{
    size_t next = *capacity == 0 ? 4 : *capacity;
    void *grown;
    while (next < needed) {
        if (next > ((size_t)-1) / 2)
            return -1;
        next *= 2;
    }
    grown = realloc(*data, next * item_size);
    if (grown == NULL)
        return -1;
    *data = grown;
    *capacity = next;
    return 0;
}

static int append_rule(Grammar *grammar, Rule **out)
{
    if (grow_array((void **)&grammar->rules, &grammar->rule_capacity, sizeof(*grammar->rules),
                   grammar->rule_count + 1) != 0)
        return -1;
    *out = &grammar->rules[grammar->rule_count++];
    memset(*out, 0, sizeof(**out));
    return 0;
}

static int append_alternative(Rule *rule, Alternative **out)
{
    if (grow_array((void **)&rule->alternatives, &rule->capacity, sizeof(*rule->alternatives),
                   rule->count + 1) != 0)
        return -1;
    *out = &rule->alternatives[rule->count++];
    memset(*out, 0, sizeof(**out));
    return 0;
}

static int append_symbol(Alternative *alternative, GrammarSymbol symbol)
{
    if (grow_array((void **)&alternative->symbols, &alternative->capacity, sizeof(*alternative->symbols),
                   alternative->count + 1) != 0)
        return -1;
    alternative->symbols[alternative->count++] = symbol;
    return 0;
}

static size_t find_rule(const Grammar *grammar, const char *name)
{
    size_t i;
    for (i = 0; i < grammar->rule_count; i++)
        if (strcmp(grammar->rules[i].name, name) == 0)
            return i;
    return (size_t)-1;
}

static int token_kind_from_name(const char *name, GrammarTokenKind *kind)
{
    if (strcmp(name, "IDENT") == 0) *kind = TOK_IDENT;
    else if (strcmp(name, "STRING") == 0) *kind = TOK_STRING;
    else if (strcmp(name, "TEXT") == 0) *kind = TOK_TEXT;
    else return -1;
    return 0;
}

static int parse_directives(GrammarParser *parser)
{
    if (parser->current.kind != G_PERCENT || strcmp(parser->current.text, "start") != 0) {
        parse_error(parser, "first directive must be %start NAME");
        return -1;
    }
    if (parser_advance(parser) != 0 || parser->current.kind != G_IDENT) {
        parse_error(parser, "expected start rule name");
        return -1;
    }
    parser->grammar->start_name = copy_text(parser->current.text, strlen(parser->current.text));
    if (parser->grammar->start_name == NULL) {
        parse_error(parser, "out of memory");
        return -1;
    }
    if (parser_advance(parser) != 0)
        return -1;
    while (parser->current.kind == G_PERCENT) {
        GrammarTokenKind kind;
        if (strcmp(parser->current.text, "token") != 0) {
            parse_error(parser, "unknown directive");
            return -1;
        }
        if (parser_advance(parser) != 0 || parser->current.kind != G_IDENT) {
            parse_error(parser, "expected token kind");
            return -1;
        }
        if (token_kind_from_name(parser->current.text, &kind) != 0) {
            parse_error(parser, "token kind must be IDENT, STRING, or TEXT");
            return -1;
        }
        if (parser->grammar->declared_tokens[kind]) {
            parse_error(parser, "duplicate token declaration");
            return -1;
        }
        parser->grammar->declared_tokens[kind] = 1;
        if (parser_advance(parser) != 0)
            return -1;
    }
    return 0;
}

static int parse_rules(GrammarParser *parser)
{
    while (parser->current.kind == G_IDENT) {
        Rule *rule;
        if (find_rule(parser->grammar, parser->current.text) != (size_t)-1) {
            parse_error(parser, "duplicate rule");
            return -1;
        }
        if (append_rule(parser->grammar, &rule) != 0) {
            parse_error(parser, "out of memory");
            return -1;
        }
        rule->name = copy_text(parser->current.text, strlen(parser->current.text));
        if (rule->name == NULL) {
            parse_error(parser, "out of memory");
            return -1;
        }
        if (parser_advance(parser) != 0 || parser->current.kind != G_ASSIGN) {
            parse_error(parser, "expected ::= after rule name");
            return -1;
        }
        if (parser_advance(parser) != 0)
            return -1;
        for (;;) {
            Alternative *alternative;
            if (append_alternative(rule, &alternative) != 0) {
                parse_error(parser, "out of memory");
                return -1;
            }
            while (parser->current.kind == G_IDENT || parser->current.kind == G_STRING ||
                   parser->current.kind == G_DOLLAR) {
                GrammarSymbol symbol;
                memset(&symbol, 0, sizeof(symbol));
                if (parser->current.kind == G_IDENT) {
                    symbol.kind = SYM_NONTERM;
                    symbol.text = copy_text(parser->current.text, strlen(parser->current.text));
                } else if (parser->current.kind == G_STRING) {
                    symbol.kind = SYM_LITERAL;
                    symbol.text = copy_text(parser->current.text, strlen(parser->current.text));
                } else {
                    GrammarTokenKind kind;
                    if (parser_advance(parser) != 0 || parser->current.kind != G_IDENT) {
                        parse_error(parser, "expected token kind after $");
                        return -1;
                    }
                    if (token_kind_from_name(parser->current.text, &kind) != 0 ||
                        !parser->grammar->declared_tokens[kind]) {
                        parse_error(parser, "$ reference uses an undeclared token kind");
                        return -1;
                    }
                    symbol.kind = SYM_TOKEN;
                    symbol.token_kind = kind;
                }
                if (symbol.kind != SYM_TOKEN && symbol.text == NULL) {
                    parse_error(parser, "out of memory");
                    return -1;
                }
                if (append_symbol(alternative, symbol) != 0) {
                    free(symbol.text);
                    parse_error(parser, "out of memory");
                    return -1;
                }
                if (parser_advance(parser) != 0)
                    return -1;
            }
            if (parser->current.kind == G_PIPE) {
                if (parser_advance(parser) != 0)
                    return -1;
                continue;
            }
            if (parser->current.kind != G_SEMI) {
                parse_error(parser, "expected | or ; in production");
                return -1;
            }
            if (parser_advance(parser) != 0)
                return -1;
            break;
        }
    }
    if (parser->grammar->rule_count == 0) {
        parse_error(parser, "grammar has no productions");
        return -1;
    }
    if (parser->current.kind != G_EOF) {
        parse_error(parser, "unexpected grammar input");
        return -1;
    }
    return 0;
}

static int validate_grammar(Grammar *grammar, Diagnostic *diagnostic)
{
    size_t i;
    size_t *nullable;
    unsigned char *edges;
    size_t *indegree;
    size_t *queue;
    int changed;
    if (find_rule(grammar, grammar->start_name) == (size_t)-1) {
        diagnostic_set(diagnostic, (Location){0, 1, 1}, "start rule is not defined");
        return -1;
    }
    grammar->start_rule = find_rule(grammar, grammar->start_name);
    for (i = 0; i < grammar->rule_count; i++) {
        size_t j;
        for (j = 0; j < grammar->rules[i].count; j++) {
            size_t k;
            Alternative *alt = &grammar->rules[i].alternatives[j];
            for (k = 0; k < alt->count; k++) {
                GrammarSymbol *symbol = &alt->symbols[k];
                if (symbol->kind == SYM_NONTERM && find_rule(grammar, symbol->text) == (size_t)-1) {
                    diagnostic_setf(diagnostic, (Location){0, 1, 1}, "undefined nonterminal: %s", symbol->text);
                    return -1;
                }
            }
        }
    }
    nullable = (size_t *)calloc(grammar->rule_count, sizeof(*nullable));
    edges = (unsigned char *)calloc(grammar->rule_count * grammar->rule_count, sizeof(*edges));
    indegree = (size_t *)calloc(grammar->rule_count, sizeof(*indegree));
    queue = (size_t *)calloc(grammar->rule_count, sizeof(*queue));
    if (nullable == NULL || edges == NULL || indegree == NULL || queue == NULL) {
        free(nullable); free(edges); free(indegree); free(queue);
        diagnostic_set(diagnostic, (Location){0, 1, 1}, "out of memory");
        return -1;
    }
    do {
        changed = 0;
        for (i = 0; i < grammar->rule_count; i++) {
            size_t j;
            for (j = 0; j < grammar->rules[i].count; j++) {
                size_t k;
                int can_empty = 1;
                Alternative *alt = &grammar->rules[i].alternatives[j];
                for (k = 0; k < alt->count; k++) {
                    if (alt->symbols[k].kind != SYM_NONTERM ||
                        !nullable[find_rule(grammar, alt->symbols[k].text)]) {
                        can_empty = 0;
                        break;
                    }
                }
                if (can_empty && !nullable[i]) {
                    nullable[i] = 1;
                    changed = 1;
                }
            }
        }
    } while (changed);
    for (i = 0; i < grammar->rule_count; i++) {
        size_t j;
        for (j = 0; j < grammar->rules[i].count; j++) {
            size_t k;
            Alternative *alt = &grammar->rules[i].alternatives[j];
            for (k = 0; k < alt->count; k++) {
                GrammarSymbol *symbol = &alt->symbols[k];
                if (symbol->kind != SYM_NONTERM)
                    break;
                edges[i * grammar->rule_count + find_rule(grammar, symbol->text)] = 1;
                if (!nullable[find_rule(grammar, symbol->text)])
                    break;
            }
        }
    }
    /* A topological traversal detects every cycle without a fixed rule-depth limit. */
    {
        size_t head = 0;
        size_t tail = 0;
        size_t removed = 0;
        size_t node;
        for (i = 0; i < grammar->rule_count; i++) {
            size_t target;
            for (target = 0; target < grammar->rule_count; target++)
                if (edges[i * grammar->rule_count + target])
                    indegree[target]++;
        }
        for (i = 0; i < grammar->rule_count; i++)
            if (indegree[i] == 0)
                queue[tail++] = i;
        while (head < tail) {
            node = queue[head++];
            removed++;
            for (i = 0; i < grammar->rule_count; i++) {
                if (edges[node * grammar->rule_count + i] && --indegree[i] == 0)
                    queue[tail++] = i;
            }
        }
        if (removed != grammar->rule_count) {
            for (i = 0; i < grammar->rule_count; i++)
                if (indegree[i] != 0)
                    break;
            diagnostic_setf(diagnostic, (Location){0, 1, 1}, "left recursion involving: %s",
                            grammar->rules[i].name);
            free(nullable); free(edges); free(indegree); free(queue);
            return -1;
        }
    }
    free(nullable); free(edges); free(indegree); free(queue);
    return 0;
}

int grammar_parse(const char *source, size_t length, Grammar *grammar, Diagnostic *diagnostic)
{
    GrammarParser parser;
    memset(grammar, 0, sizeof(*grammar));
    memset(diagnostic, 0, sizeof(*diagnostic));
    parser.lexer.source = source;
    parser.lexer.length = length;
    parser.lexer.pos = 0;
    parser.lexer.loc = (Location){0, 1, 1};
    parser.lexer.diagnostic = diagnostic;
    parser.current.kind = G_EOF;
    parser.current.text = NULL;
    parser.grammar = grammar;
    parser.diagnostic = diagnostic;
    parser_advance(&parser);
    if (!diagnostic->present && parse_directives(&parser) == 0 && parse_rules(&parser) == 0)
        (void)validate_grammar(grammar, diagnostic);
    grammar_token_free(&parser.current);
    if (diagnostic->present) {
        grammar_free(grammar);
        return -1;
    }
    return 0;
}

int grammar_set_start(Grammar *grammar, const char *name, Diagnostic *diagnostic)
{
    size_t index = find_rule(grammar, name);
    if (index == (size_t)-1) {
        diagnostic_setf(diagnostic, (Location){0, 1, 1}, "start override is not defined: %s", name);
        return -1;
    }
    free(grammar->start_name);
    grammar->start_name = copy_text(name, strlen(name));
    if (grammar->start_name == NULL) {
        diagnostic_set(diagnostic, (Location){0, 1, 1}, "out of memory");
        return -1;
    }
    grammar->start_rule = index;
    return 0;
}

void grammar_free(Grammar *grammar)
{
    size_t i;
    for (i = 0; i < grammar->rule_count; i++) {
        size_t j;
        Rule *rule = &grammar->rules[i];
        free(rule->name);
        for (j = 0; j < rule->count; j++) {
            size_t k;
            for (k = 0; k < rule->alternatives[j].count; k++)
                free(rule->alternatives[j].symbols[k].text);
            free(rule->alternatives[j].symbols);
        }
        free(rule->alternatives);
    }
    free(grammar->rules);
    free(grammar->start_name);
    memset(grammar, 0, sizeof(*grammar));
}
