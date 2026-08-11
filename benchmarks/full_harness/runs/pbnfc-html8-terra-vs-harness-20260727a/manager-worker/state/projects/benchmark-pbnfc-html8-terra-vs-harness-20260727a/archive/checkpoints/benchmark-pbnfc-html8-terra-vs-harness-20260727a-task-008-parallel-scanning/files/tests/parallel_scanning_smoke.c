#include "grammar_ast.h"
#include "markup_lexer.h"
#include "recognizer.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "parallel scanning smoke: %s\n", detail);
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
            size_t next_capacity = capacity == 0U ? 4U : capacity * 2U;
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

static int check_scan_distribution(const PbnfcRecognitionStats *stats)
{
    size_t worker_index;

    if (stats->workers != PBNFC_WORKER_POOL_SIZE ||
        stats->active_workers != PBNFC_WORKER_POOL_SIZE ||
        stats->rounds == 0U) {
        return fail("parallel run did not use eight workers");
    }
    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        if (stats->scan_tasks[worker_index] == 0U) {
            return fail("a worker did not scan a chart item");
        }
        if (stats->tasks[worker_index] < stats->scan_tasks[worker_index]) {
            return fail("scan work exceeded total work");
        }
    }
    return 0;
}

int main(void)
{
    static const char grammar_source[] =
        "%start Document\n"
        "%token TEXT\n"
        "Document ::= $TEXT | $TEXT | $TEXT | $TEXT | $TEXT | $TEXT | $TEXT | $TEXT ;\n";
    static const char input_source[] = "parallel scan";
    PbnfcGrammar *grammar = parse_grammar(grammar_source);
    PbnfcMarkupToken *tokens = NULL;
    size_t token_count = 0U;
    PbnfcRecognitionStats stats;
    PbnfcRecognitionResult result;

    if (grammar == NULL || !lex_input(input_source, &tokens, &token_count)) {
        pbnfc_grammar_free(grammar);
        free(tokens);
        return fail("scan smoke input did not prepare");
    }
    result = pbnfc_recognize_parallel(grammar,
                                      tokens,
                                      token_count,
                                      NULL,
                                      &stats);
    if (result != PBNFC_RECOGNITION_ACCEPTED ||
        check_scan_distribution(&stats) != 0) {
        free(tokens);
        pbnfc_grammar_free(grammar);
        return fail("parallel scan did not distribute terminal work");
    }
    free(tokens);
    pbnfc_grammar_free(grammar);
    return 0;
}
