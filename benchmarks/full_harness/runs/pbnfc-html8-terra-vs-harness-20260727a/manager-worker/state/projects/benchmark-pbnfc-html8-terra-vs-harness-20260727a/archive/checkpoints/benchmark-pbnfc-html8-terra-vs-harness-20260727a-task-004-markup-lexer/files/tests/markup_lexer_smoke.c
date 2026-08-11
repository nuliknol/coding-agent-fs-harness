#include "markup_lexer.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    PbnfcMarkupTokenKind kind;
    size_t offset;
    size_t line;
    size_t column;
    const char *text;
} ExpectedToken;

static int fail_at(size_t index, const char *detail)
{
    (void)fprintf(stderr, "markup lexer smoke token %zu: %s\n", index, detail);
    return 1;
}

int main(void)
{
    static const char source[] =
        "<a href=target>\n"
        "  <img src=x.png/>";
    static const ExpectedToken expected[] = {
        {PBNFC_MARKUP_TOKEN_LESS_THAN, 0U, 1U, 1U, "<"},
        {PBNFC_MARKUP_TOKEN_IDENT, 1U, 1U, 2U, "a"},
        {PBNFC_MARKUP_TOKEN_IDENT, 3U, 1U, 4U, "href"},
        {PBNFC_MARKUP_TOKEN_EQUALS, 7U, 1U, 8U, "="},
        {PBNFC_MARKUP_TOKEN_IDENT, 8U, 1U, 9U, "target"},
        {PBNFC_MARKUP_TOKEN_GREATER_THAN, 14U, 1U, 15U, ">"},
        {PBNFC_MARKUP_TOKEN_LESS_THAN, 18U, 2U, 3U, "<"},
        {PBNFC_MARKUP_TOKEN_IDENT, 19U, 2U, 4U, "img"},
        {PBNFC_MARKUP_TOKEN_IDENT, 23U, 2U, 8U, "src"},
        {PBNFC_MARKUP_TOKEN_EQUALS, 26U, 2U, 11U, "="},
        {PBNFC_MARKUP_TOKEN_IDENT, 27U, 2U, 12U, "x.png"},
        {PBNFC_MARKUP_TOKEN_SLASH, 32U, 2U, 17U, "/"},
        {PBNFC_MARKUP_TOKEN_GREATER_THAN, 33U, 2U, 18U, ">"},
        {PBNFC_MARKUP_TOKEN_EOF, 34U, 2U, 19U, ""}
    };
    PbnfcMarkupLexer lexer;
    PbnfcMarkupToken token;
    size_t index;

    pbnfc_markup_lexer_init(&lexer, source, strlen(source));
    for (index = 0U;
         index < sizeof(expected) / sizeof(expected[0]);
         ++index) {
        if (!pbnfc_markup_lexer_next(&lexer, &token)) {
            return fail_at(index, "unexpected lexer failure");
        }
        if (token.kind != expected[index].kind ||
            token.location.byte_offset != expected[index].offset ||
            token.location.line != expected[index].line ||
            token.location.column != expected[index].column ||
            token.length != strlen(expected[index].text) ||
            strncmp(token.text, expected[index].text, token.length) != 0) {
            return fail_at(index, "token, lexeme, or location mismatch");
        }
    }
    if (pbnfc_markup_lexer_failed(&lexer)) {
        return fail_at(index, "lexer failed after the expected EOF");
    }
    if (!pbnfc_markup_lexer_next(&lexer, &token) ||
        token.kind != PBNFC_MARKUP_TOKEN_EOF) {
        return fail_at(index, "lexer did not remain at EOF");
    }
    return 0;
}
