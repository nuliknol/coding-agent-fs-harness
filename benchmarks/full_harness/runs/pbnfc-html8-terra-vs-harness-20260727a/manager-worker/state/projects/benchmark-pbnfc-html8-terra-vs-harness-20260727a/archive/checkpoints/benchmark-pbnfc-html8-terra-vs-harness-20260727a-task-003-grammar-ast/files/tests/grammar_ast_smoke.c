#include "grammar_ast.h"

#include <stdio.h>
#include <string.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "grammar AST smoke: %s\n", detail);
    return 1;
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
    return 0;
}
