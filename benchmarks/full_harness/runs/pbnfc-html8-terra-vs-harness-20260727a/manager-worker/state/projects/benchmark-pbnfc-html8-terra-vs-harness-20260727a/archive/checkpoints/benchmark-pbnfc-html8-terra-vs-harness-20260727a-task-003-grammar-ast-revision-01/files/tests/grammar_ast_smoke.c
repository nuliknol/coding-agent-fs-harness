#include "grammar_ast.h"

#include <stdio.h>
#include <string.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "grammar AST smoke: %s\n", detail);
    return 1;
}

typedef struct {
    const char *source;
    const char *detail;
    size_t offset;
    size_t line;
    size_t column;
} ValidationCase;

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

static int check_validation_case(size_t index, const ValidationCase *test_case)
{
    PbnfcDiagnosticContext diagnostics;
    PbnfcGrammar *grammar = NULL;
    FILE *stream = tmpfile();
    char diagnostic[256];
    char location[96];
    size_t length;
    size_t line_count = 0U;
    size_t cursor;

    if (stream == NULL) {
        return fail("could not create validation diagnostic stream");
    }
    pbnfc_diagnostic_context_init(&diagnostics, stream);
    if (!pbnfc_grammar_parse(test_case->source,
                             strlen(test_case->source),
                             NULL,
                             &grammar)) {
        (void)fclose(stream);
        return fail("validation case did not parse");
    }
    if (pbnfc_grammar_validate(grammar, &diagnostics)) {
        pbnfc_grammar_free(grammar);
        (void)fclose(stream);
        (void)fprintf(stderr,
                      "grammar AST validation case %zu: invalid grammar accepted\n",
                      index);
        return 1;
    }
    pbnfc_grammar_free(grammar);

    length = read_diagnostic(stream, diagnostic, sizeof(diagnostic));
    (void)snprintf(location,
                   sizeof(location),
                   "offset=%zu line=%zu column=%zu",
                   test_case->offset,
                   test_case->line,
                   test_case->column);
    for (cursor = 0U; cursor < length; ++cursor) {
        if (diagnostic[cursor] == '\n') {
            ++line_count;
        }
    }
    if (line_count != 1U ||
        strncmp(diagnostic, "GRAMMAR_ERROR ", 14U) != 0 ||
        strstr(diagnostic, test_case->detail) == NULL ||
        strstr(diagnostic, location) == NULL) {
        (void)fclose(stream);
        (void)fprintf(stderr,
                      "grammar AST validation case %zu: diagnostic mismatch: %s",
                      index,
                      diagnostic);
        return 1;
    }
    (void)fclose(stream);
    return 0;
}

int main(void)
{
    static const char source[] =
        "%start Document\n"
        "%token TEXT\n"
        "%token IDENT\n"
        "Document ::= Item Items | ;\n"
        "Items ::= Item Items | ;\n"
        "Item ::= 'open\\'tag' $TEXT Name ;\n"
        "Name ::= Bare | ;\n"
        "Bare ::= Name ;\n";
    PbnfcGrammar *grammar = NULL;
    PbnfcGrammarProduction *document;
    PbnfcGrammarProduction *item;
    PbnfcGrammarProduction *name;
    PbnfcGrammarAlternative *alternative;

    if (!pbnfc_grammar_parse(source, sizeof(source) - 1U, NULL, &grammar)) {
        return fail("representative grammar was rejected");
    }
    if (!pbnfc_grammar_validate(grammar, NULL)) {
        pbnfc_grammar_free(grammar);
        return fail("representative grammar failed validation");
    }
    if (grammar->start_count != 1U ||
        grammar->start_name == NULL ||
        strcmp(grammar->start_name, "Document") != 0 ||
        grammar->token_declaration_count != 2U ||
        strcmp(grammar->token_declarations[0].name, "TEXT") != 0 ||
        strcmp(grammar->token_declarations[1].name, "IDENT") != 0 ||
        grammar->production_count != 5U) {
        pbnfc_grammar_free(grammar);
        return fail("declarations or production count was not retained");
    }

    document = &grammar->productions[0];
    if (strcmp(document->name, "Document") != 0 ||
        document->alternative_count != 2U ||
        document->alternatives[0].symbol_count != 2U ||
        document->alternatives[1].symbol_count != 0U ||
        document->alternatives[0].symbols[0].kind !=
            PBNFC_GRAMMAR_SYMBOL_NONTERMINAL ||
        strcmp(document->alternatives[0].symbols[0].name, "Item") != 0) {
        pbnfc_grammar_free(grammar);
        return fail("alternatives or epsilon was not retained");
    }

    item = &grammar->productions[2];
    alternative = &item->alternatives[0];
    if (alternative->symbol_count != 3U ||
        alternative->symbols[0].kind != PBNFC_GRAMMAR_SYMBOL_TERMINAL ||
        strcmp(alternative->symbols[0].name, "open'tag") != 0 ||
        alternative->symbols[1].kind != PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE ||
        strcmp(alternative->symbols[1].name, "TEXT") != 0 ||
        alternative->symbols[2].kind != PBNFC_GRAMMAR_SYMBOL_NONTERMINAL ||
        strcmp(alternative->symbols[2].name, "Name") != 0) {
        pbnfc_grammar_free(grammar);
        return fail("symbol kinds or owned symbol values were not retained");
    }

    name = &grammar->productions[3];
    if (name->alternative_count != 2U ||
        name->alternatives[1].symbol_count != 0U) {
        pbnfc_grammar_free(grammar);
        return fail("second epsilon alternative was not retained");
    }
    pbnfc_grammar_free(grammar);

    {
        static const ValidationCase cases[] = {
            {"%token TEXT\nDocument ::= ;\n",
             "grammar requires exactly one %start declaration",
             7U,
             1U,
             8U},
            {"%token TEXT\n%start Document\nDocument ::= ;\n",
             "the %start declaration must be the first directive",
             19U,
             2U,
             8U},
            {"%start Document\n%start Other\nDocument ::= ;\n",
             "grammar requires exactly one %start declaration",
             23U,
             2U,
             8U},
            {"%start Document\n%token TEXT\n%token TEXT\nDocument ::= ;\n",
             "duplicate token declaration",
             35U,
             3U,
             8U},
            {"%start Document\nDocument ::= ;\nDocument ::= ;\n",
             "duplicate rule definition",
             31U,
             3U,
             1U},
            {"%start Document\nDocument ::= Missing ;\n",
             "undefined nonterminal reference",
             29U,
             2U,
             14U},
            {"%start Document\nDocument ::= $TEXT ;\n",
             "undefined token reference",
             29U,
             2U,
             14U}
        };
        size_t index;

        for (index = 0U; index < sizeof(cases) / sizeof(cases[0]); ++index) {
            if (check_validation_case(index, &cases[index]) != 0) {
                return 1;
            }
        }
    }
    return 0;
}
