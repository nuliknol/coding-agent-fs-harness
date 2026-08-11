#include "grammar_ast.h"
#include "markup_lexer.h"
#include "recognizer.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "sequential recognizer smoke: %s\n", detail);
    return 1;
}

static PbnfcGrammar *parse_grammar(const char *source)
{
    PbnfcGrammar *grammar = NULL;

    if (!pbnfc_grammar_parse(source, strlen(source), NULL, &grammar) ||
        !pbnfc_grammar_validate(grammar, NULL)) {
        pbnfc_grammar_free(grammar);
        return NULL;
    }
    return grammar;
}

static bool lex_input(const char *source,
                      PbnfcMarkupToken **tokens_out,
                      size_t *count_out)
{
    PbnfcMarkupLexer lexer;
    PbnfcMarkupToken token;
    PbnfcMarkupToken *tokens = NULL;
    size_t count = 0U;
    size_t capacity = 0U;

    pbnfc_markup_lexer_init(&lexer, source, strlen(source), NULL);
    for (;;) {
        if (!pbnfc_markup_lexer_next(&lexer, &token)) {
            free(tokens);
            return false;
        }
        if (token.kind == PBNFC_MARKUP_TOKEN_EOF) {
            break;
        }
        if (count == capacity) {
            size_t next_capacity = capacity == 0U ? 8U : capacity * 2U;
            PbnfcMarkupToken *next_tokens =
                (PbnfcMarkupToken *)realloc(tokens,
                                             next_capacity * sizeof(*tokens));
            if (next_tokens == NULL) {
                free(tokens);
                return false;
            }
            tokens = next_tokens;
            capacity = next_capacity;
        }
        tokens[count] = token;
        ++count;
    }
    *tokens_out = tokens;
    *count_out = count;
    return true;
}

static int check_case(const PbnfcGrammar *grammar,
                      const char *source,
                      PbnfcRecognitionResult expected,
                      const char *detail)
{
    PbnfcMarkupToken *tokens = NULL;
    size_t token_count = 0U;
    PbnfcRecognitionResult actual;

    if (!lex_input(source, &tokens, &token_count)) {
        return fail("markup test input did not lex");
    }
    actual = pbnfc_recognize_sequential(grammar,
                                        tokens,
                                        token_count,
                                        NULL);
    free(tokens);
    if (actual != expected) {
        return fail(detail);
    }
    return 0;
}

int main(void)
{
    static const char nested_grammar[] =
        "%start Document\n"
        "%token TEXT\n"
        "Document ::= Nodes ;\n"
        "Nodes ::= Node Nodes | ;\n"
        "Node ::= Text | Group ;\n"
        "Text ::= $TEXT ;\n"
        "Group ::= '<' 'a' '>' Nodes '<' '/' 'a' '>' ;\n";
    static const char empty_grammar[] =
        "%start Empty\n"
        "Empty ::= ;\n";
    PbnfcGrammar *nested = parse_grammar(nested_grammar);
    PbnfcGrammar *empty = parse_grammar(empty_grammar);

    if (nested == NULL || empty == NULL) {
        pbnfc_grammar_free(nested);
        pbnfc_grammar_free(empty);
        return fail("recognizer smoke grammar was rejected");
    }
    if (check_case(nested,
                   "<a>Hello<a>world</a></a>",
                   PBNFC_RECOGNITION_ACCEPTED,
                   "nested right-recursive input was rejected") != 0 ||
        check_case(nested,
                   "<a>Hello",
                   PBNFC_RECOGNITION_REJECTED,
                   "incomplete input was accepted") != 0 ||
        check_case(nested,
                   "<a>Hello</a><a>",
                   PBNFC_RECOGNITION_REJECTED,
                   "unconsumed input was accepted") != 0 ||
        check_case(empty,
                   "",
                   PBNFC_RECOGNITION_ACCEPTED,
                   "epsilon grammar did not accept empty input") != 0) {
        pbnfc_grammar_free(nested);
        pbnfc_grammar_free(empty);
        return 1;
    }
    pbnfc_grammar_free(nested);
    pbnfc_grammar_free(empty);
    return 0;
}
