#include "grammar_lexer.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    PbnfcGrammarTokenKind kind;
    size_t offset;
    size_t line;
    size_t column;
    const char *text;
} ExpectedToken;

static int fail_at(size_t index, const char *message)
{
    (void)fprintf(stderr, "lexer smoke token %zu: %s\n", index, message);
    return 1;
}

int main(void)
{
    static const char grammar[] =
        "# header\n"
        "%start Document\n"
        "%token TEXT # token kind\n"
        "Document ::= Node | ;\n"
        "Node ::= Leaf ;\n";
    static const ExpectedToken expected[] = {
        {PBNFC_GRAMMAR_TOKEN_START_DIRECTIVE, 9U, 2U, 1U, "%start"},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 16U, 2U, 8U, "Document"},
        {PBNFC_GRAMMAR_TOKEN_TOKEN_DIRECTIVE, 25U, 3U, 1U, "%token"},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 32U, 3U, 8U, "TEXT"},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 50U, 4U, 1U, "Document"},
        {PBNFC_GRAMMAR_TOKEN_ASSIGN, 59U, 4U, 10U, "::="},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 63U, 4U, 14U, "Node"},
        {PBNFC_GRAMMAR_TOKEN_PIPE, 68U, 4U, 19U, "|"},
        {PBNFC_GRAMMAR_TOKEN_SEMICOLON, 70U, 4U, 21U, ";"},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 72U, 5U, 1U, "Node"},
        {PBNFC_GRAMMAR_TOKEN_ASSIGN, 77U, 5U, 6U, "::="},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 81U, 5U, 10U, "Leaf"},
        {PBNFC_GRAMMAR_TOKEN_SEMICOLON, 86U, 5U, 15U, ";"},
        {PBNFC_GRAMMAR_TOKEN_EOF, 88U, 6U, 1U, ""}
    };
    PbnfcGrammarLexer lexer;
    PbnfcGrammarToken token;
    size_t index = 0U;

    pbnfc_grammar_lexer_init(&lexer, grammar, sizeof(grammar) - 1U, NULL);
    while (index < sizeof(expected) / sizeof(expected[0])) {
        if (!pbnfc_grammar_lexer_next(&lexer, &token)) {
            return fail_at(index, "unexpected lexer failure");
        }
        if (token.kind != expected[index].kind ||
            token.location.byte_offset != expected[index].offset ||
            token.location.line != expected[index].line ||
            token.location.column != expected[index].column ||
            token.length != strlen(expected[index].text) ||
            strncmp(token.text, expected[index].text, token.length) != 0) {
            return fail_at(index, "token or source location mismatch");
        }
        ++index;
    }
    if (pbnfc_grammar_lexer_failed(&lexer)) {
        return fail_at(index, "lexer failed after the expected EOF");
    }

    return 0;
}
