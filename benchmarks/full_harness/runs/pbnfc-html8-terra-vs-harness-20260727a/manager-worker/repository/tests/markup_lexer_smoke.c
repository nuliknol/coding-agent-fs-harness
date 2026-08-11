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

typedef struct {
    const char *source;
    const char *detail;
    size_t offset;
    size_t line;
    size_t column;
} ExpectedError;

static int fail_at(size_t index, const char *detail)
{
    (void)fprintf(stderr, "markup lexer smoke token %zu: %s\n", index, detail);
    return 1;
}

static int check_source(const char *source,
                        const ExpectedToken *expected,
                        size_t expected_count)
{
    PbnfcMarkupLexer lexer;
    PbnfcMarkupToken token;
    size_t index;

    pbnfc_markup_lexer_init(&lexer, source, strlen(source), NULL);
    for (index = 0U;
         index < expected_count;
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

static size_t read_diagnostic(FILE *stream, char *buffer, size_t capacity)
{
    size_t length = 0U;
    int character;

    rewind(stream);
    while (length + 1U < capacity &&
           (character = fgetc(stream)) != EOF) {
        buffer[length] = (char)character;
        ++length;
    }
    buffer[length] = '\0';
    return length;
}

static int check_error_case(size_t index, const ExpectedError *expected)
{
    PbnfcDiagnosticContext diagnostics;
    PbnfcMarkupLexer lexer;
    PbnfcMarkupToken token;
    FILE *stream = tmpfile();
    char diagnostic[256];
    char expected_line[256];
    size_t length;
    size_t line_count = 0U;
    size_t cursor;

    if (stream == NULL) {
        return fail_at(index, "could not create diagnostic stream");
    }
    pbnfc_diagnostic_context_init(&diagnostics, stream);
    pbnfc_markup_lexer_init(&lexer,
                            expected->source,
                            strlen(expected->source),
                            &diagnostics);
    for (;;) {
        if (!pbnfc_markup_lexer_next(&lexer, &token)) {
            break;
        }
        if (token.kind == PBNFC_MARKUP_TOKEN_EOF) {
            (void)fclose(stream);
            return fail_at(index, "malformed input was accepted");
        }
    }
    if (!pbnfc_markup_lexer_failed(&lexer)) {
        (void)fclose(stream);
        return fail_at(index, "lexer did not enter failed state");
    }
    if (pbnfc_markup_lexer_next(&lexer, &token)) {
        (void)fclose(stream);
        return fail_at(index, "failed lexer produced another token");
    }

    length = read_diagnostic(stream, diagnostic, sizeof(diagnostic));
    (void)snprintf(expected_line,
                   sizeof(expected_line),
                   "GRAMMAR_ERROR %s offset=%zu line=%zu column=%zu\n",
                   expected->detail,
                   expected->offset,
                   expected->line,
                   expected->column);
    for (cursor = 0U; cursor < length; ++cursor) {
        if (diagnostic[cursor] == '\n') {
            ++line_count;
        }
    }
    if (line_count != 1U || strcmp(diagnostic, expected_line) != 0) {
        (void)fclose(stream);
        return fail_at(index, "diagnostic text or location mismatch");
    }
    (void)fclose(stream);
    return 0;
}

int main(void)
{
    static const char core_source[] =
        "<a href=target>\n"
        "  <img src=x.png/>";
    static const ExpectedToken core_expected[] = {
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
    static const char values_source[] =
        "<a title=\"say \\\"hi\\\" and \\\\path\" note='it\\'s \\\\ok'>"
        "Hello world"
        "</a>";
    static const ExpectedToken values_expected[] = {
        {PBNFC_MARKUP_TOKEN_LESS_THAN, 0U, 1U, 1U, "<"},
        {PBNFC_MARKUP_TOKEN_IDENT, 1U, 1U, 2U, "a"},
        {PBNFC_MARKUP_TOKEN_IDENT, 3U, 1U, 4U, "title"},
        {PBNFC_MARKUP_TOKEN_EQUALS, 8U, 1U, 9U, "="},
        {PBNFC_MARKUP_TOKEN_STRING, 9U, 1U, 10U,
         "\"say \\\"hi\\\" and \\\\path\""},
        {PBNFC_MARKUP_TOKEN_IDENT, 33U, 1U, 34U, "note"},
        {PBNFC_MARKUP_TOKEN_EQUALS, 37U, 1U, 38U, "="},
        {PBNFC_MARKUP_TOKEN_STRING, 38U, 1U, 39U, "'it\\'s \\\\ok'"},
        {PBNFC_MARKUP_TOKEN_GREATER_THAN, 50U, 1U, 51U, ">"},
        {PBNFC_MARKUP_TOKEN_TEXT, 51U, 1U, 52U, "Hello world"},
        {PBNFC_MARKUP_TOKEN_LESS_THAN, 62U, 1U, 63U, "<"},
        {PBNFC_MARKUP_TOKEN_SLASH, 63U, 1U, 64U, "/"},
        {PBNFC_MARKUP_TOKEN_IDENT, 64U, 1U, 65U, "a"},
        {PBNFC_MARKUP_TOKEN_GREATER_THAN, 65U, 1U, 66U, ">"},
        {PBNFC_MARKUP_TOKEN_EOF, 66U, 1U, 67U, ""}
    };
    static const char invalid_byte_source[] = "<a " "\xFF" ">";
    static const ExpectedError errors[] = {
        {"<a\n", "unterminated markup tag", 3U, 2U, 1U},
        {"<a title=\"oops", "unterminated markup quoted value",
         9U, 1U, 10U},
        {"<a title=\"bad\\q\">", "invalid markup value escape",
         9U, 1U, 10U},
        {invalid_byte_source, "invalid markup byte", 3U, 1U, 4U},
        {"<a =x>", "invalid markup tag transition", 3U, 1U, 4U},
        {"</a x>", "invalid markup tag transition", 4U, 1U, 5U}
    };
    size_t error_index;

    if (check_source(core_source,
                     core_expected,
                     sizeof(core_expected) / sizeof(core_expected[0])) != 0) {
        return 1;
    }
    if (check_source(values_source,
                     values_expected,
                     sizeof(values_expected) / sizeof(values_expected[0])) != 0) {
        return 1;
    }
    for (error_index = 0U;
         error_index < sizeof(errors) / sizeof(errors[0]);
         ++error_index) {
        if (check_error_case(error_index, &errors[error_index]) != 0) {
            return 1;
        }
    }
    return 0;
}
