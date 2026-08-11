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

typedef struct {
    const char *source;
    const char *detail;
    size_t offset;
    size_t line;
    size_t column;
} ExpectedError;

static int fail_at(size_t index, const char *message)
{
    (void)fprintf(stderr, "lexer smoke token %zu: %s\n", index, message);
    return 1;
}

static int fail_error_at(size_t index, const char *message)
{
    (void)fprintf(stderr, "lexer smoke error %zu: %s\n", index, message);
    return 1;
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
    PbnfcGrammarLexer lexer;
    PbnfcGrammarToken token;
    FILE *stream = tmpfile();
    char diagnostic[256];
    char expected_line[256];
    size_t length;
    size_t line_count = 0U;
    size_t cursor;

    if (stream == NULL) {
        return fail_error_at(index, "could not create diagnostic stream");
    }
    pbnfc_diagnostic_context_init(&diagnostics, stream);
    pbnfc_grammar_lexer_init(&lexer,
                             expected->source,
                             strlen(expected->source),
                             &diagnostics);
    if (pbnfc_grammar_lexer_next(&lexer, &token)) {
        (void)fclose(stream);
        return fail_error_at(index, "malformed input was accepted");
    }
    if (!pbnfc_grammar_lexer_failed(&lexer)) {
        (void)fclose(stream);
        return fail_error_at(index, "lexer did not enter failed state");
    }
    if (pbnfc_grammar_lexer_next(&lexer, &token)) {
        (void)fclose(stream);
        return fail_error_at(index, "failed lexer produced another token");
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
        return fail_error_at(index, "diagnostic text or location mismatch");
    }
    (void)fclose(stream);
    return 0;
}

int main(void)
{
    static const char grammar[] =
        "# header\n"
        "%start Document\n"
        "%token TEXT # token kind\n"
        "Document ::= Node | 'it\\'s \\\\ok' $IDENT $STRING $TEXT ;\n"
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
        {PBNFC_GRAMMAR_TOKEN_TERMINAL, 70U, 4U, 21U, "'it\\'s \\\\ok'"},
        {PBNFC_GRAMMAR_TOKEN_REFERENCE, 83U, 4U, 34U, "$IDENT"},
        {PBNFC_GRAMMAR_TOKEN_REFERENCE, 90U, 4U, 41U, "$STRING"},
        {PBNFC_GRAMMAR_TOKEN_REFERENCE, 98U, 4U, 49U, "$TEXT"},
        {PBNFC_GRAMMAR_TOKEN_SEMICOLON, 104U, 4U, 55U, ";"},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 106U, 5U, 1U, "Node"},
        {PBNFC_GRAMMAR_TOKEN_ASSIGN, 111U, 5U, 6U, "::="},
        {PBNFC_GRAMMAR_TOKEN_IDENTIFIER, 115U, 5U, 10U, "Leaf"},
        {PBNFC_GRAMMAR_TOKEN_SEMICOLON, 120U, 5U, 15U, ";"},
        {PBNFC_GRAMMAR_TOKEN_EOF, 122U, 6U, 1U, ""}
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

    {
        static const ExpectedError errors[] = {
            {"\n\t@", "invalid character in grammar", 2U, 2U, 2U},
            {"::", "expected ::= punctuation", 0U, 1U, 1U},
            {"%bogus", "unknown grammar directive", 0U, 1U, 1U},
            {"%start9", "malformed grammar directive", 0U, 1U, 1U},
            {"\n  $9", "malformed grammar token reference", 3U, 2U, 3U},
            {"\n 'unterminated", "unterminated grammar terminal", 2U, 2U, 2U},
            {"\n  'bad\\n'", "invalid grammar terminal escape", 3U, 2U, 3U}
        };
        size_t error_index;

        for (error_index = 0U;
             error_index < sizeof(errors) / sizeof(errors[0]);
             ++error_index) {
            if (check_error_case(error_index, &errors[error_index]) != 0) {
                return 1;
            }
        }
    }

    return 0;
}
