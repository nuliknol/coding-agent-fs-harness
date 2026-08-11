#include "diagnostics.h"
#include "grammar_ast.h"
#include "markup_lexer.h"
#include "recognizer.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

typedef struct {
    const char *grammar_path;
    const char *input_path;
    const char *start_name;
    bool have_grammar;
    bool have_input;
    bool have_start;
    bool have_stats;
} CliOptions;

static int command_line_error(const PbnfcDiagnosticContext *diagnostics,
                              const char *detail)
{
    (void)pbnfc_diagnostic_emit(diagnostics, detail, NULL);
    return 2;
}

static bool is_option(const char *argument)
{
    return argument[0] == '-' && argument[1] == '-';
}

static bool read_file(const char *path,
                      const char *kind,
                      char **source_out,
                      size_t *length_out,
                      const PbnfcDiagnosticContext *diagnostics)
{
    FILE *stream;
    char *source;
    size_t capacity = 4096U;
    size_t length = 0U;

    stream = fopen(path, "rb");
    if (stream == NULL) {
        (void)pbnfc_diagnostic_emit(diagnostics, kind, NULL);
        return false;
    }
    source = (char *)malloc(capacity + 1U);
    if (source == NULL) {
        (void)fclose(stream);
        (void)pbnfc_diagnostic_emit(diagnostics, "out of memory reading file", NULL);
        return false;
    }
    for (;;) {
        size_t count = fread(source + length, 1U, capacity - length, stream);

        length += count;
        if (count == 0U) {
            if (ferror(stream)) {
                free(source);
                (void)fclose(stream);
                (void)pbnfc_diagnostic_emit(diagnostics, kind, NULL);
                return false;
            }
            break;
        }
        if (length == capacity) {
            size_t next_capacity;
            char *next_source;

            if (capacity > (size_t)-1 / 2U ||
                capacity * 2U + 1U < capacity * 2U) {
                free(source);
                (void)fclose(stream);
                (void)pbnfc_diagnostic_emit(diagnostics,
                                            "file is too large",
                                            NULL);
                return false;
            }
            next_capacity = capacity * 2U;
            next_source = (char *)realloc(source, next_capacity + 1U);
            if (next_source == NULL) {
                free(source);
                (void)fclose(stream);
                (void)pbnfc_diagnostic_emit(diagnostics,
                                            "out of memory reading file",
                                            NULL);
                return false;
            }
            source = next_source;
            capacity = next_capacity;
        }
    }
    source[length] = '\0';
    (void)fclose(stream);
    *source_out = source;
    *length_out = length;
    return true;
}

static bool lex_input(const char *source,
                      size_t length,
                      const PbnfcDiagnosticContext *diagnostics,
                      PbnfcMarkupToken **tokens_out,
                      size_t *count_out)
{
    PbnfcMarkupLexer lexer;
    PbnfcMarkupToken token;
    PbnfcMarkupToken *tokens = NULL;
    size_t count = 0U;
    size_t capacity = 0U;

    pbnfc_markup_lexer_init(&lexer, source, length, diagnostics);
    for (;;) {
        if (!pbnfc_markup_lexer_next(&lexer, &token)) {
            free(tokens);
            return false;
        }
        if (token.kind == PBNFC_MARKUP_TOKEN_EOF) {
            break;
        }
        if (count == capacity) {
            size_t next_capacity = capacity == 0U ? 16U : capacity * 2U;
            PbnfcMarkupToken *next_tokens;

            if (next_capacity < capacity ||
                next_capacity > (size_t)-1 / sizeof(*tokens)) {
                free(tokens);
                (void)pbnfc_diagnostic_emit(diagnostics,
                                            "input has too many tokens",
                                            NULL);
                return false;
            }
            next_tokens = (PbnfcMarkupToken *)realloc(
                tokens, next_capacity * sizeof(*tokens));
            if (next_tokens == NULL) {
                free(tokens);
                (void)pbnfc_diagnostic_emit(diagnostics,
                                            "out of memory lexing input",
                                            NULL);
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

static void print_stats(const PbnfcRecognitionStats *stats)
{
    size_t worker_index;

    (void)fprintf(stdout,
                  " workers=%zu active_workers=%zu rounds=%zu tasks=",
                  stats->workers,
                  stats->active_workers,
                  stats->rounds);
    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        if (worker_index != 0U) {
            (void)fputc(',', stdout);
        }
        (void)fprintf(stdout, "%zu", stats->tasks[worker_index]);
    }
}

static int parse_options(int argc,
                         char **argv,
                         CliOptions *options,
                         const PbnfcDiagnosticContext *diagnostics)
{
    int index;

    for (index = 1; index < argc; ++index) {
        const char *argument = argv[index];

        if (strcmp(argument, "--grammar") == 0) {
            if (options->have_grammar) {
                return command_line_error(diagnostics, "duplicate option --grammar");
            }
            if (index + 1 >= argc || is_option(argv[index + 1])) {
                return command_line_error(diagnostics, "missing value for --grammar");
            }
            options->grammar_path = argv[++index];
            options->have_grammar = true;
        } else if (strcmp(argument, "--input") == 0) {
            if (options->have_input) {
                return command_line_error(diagnostics, "duplicate option --input");
            }
            if (index + 1 >= argc || is_option(argv[index + 1])) {
                return command_line_error(diagnostics, "missing value for --input");
            }
            options->input_path = argv[++index];
            options->have_input = true;
        } else if (strcmp(argument, "--start") == 0) {
            if (options->have_start) {
                return command_line_error(diagnostics, "duplicate option --start");
            }
            if (index + 1 >= argc || is_option(argv[index + 1])) {
                return command_line_error(diagnostics, "missing value for --start");
            }
            options->start_name = argv[++index];
            options->have_start = true;
        } else if (strcmp(argument, "--stats") == 0) {
            if (options->have_stats) {
                return command_line_error(diagnostics, "duplicate option --stats");
            }
            options->have_stats = true;
        } else if (is_option(argument)) {
            return command_line_error(diagnostics, "unknown option");
        } else {
            return command_line_error(diagnostics, "unexpected positional argument");
        }
    }

    if (!options->have_grammar) {
        return command_line_error(diagnostics, "missing required option --grammar");
    }
    if (!options->have_input) {
        return command_line_error(diagnostics, "missing required option --input");
    }

    return 0;
}

int main(int argc, char **argv)
{
    CliOptions options = {0};
    PbnfcDiagnosticContext diagnostics;
    char *grammar_source = NULL;
    char *input_source = NULL;
    size_t grammar_length = 0U;
    size_t input_length = 0U;
    PbnfcGrammar *grammar = NULL;
    PbnfcMarkupToken *tokens = NULL;
    size_t token_count = 0U;
    PbnfcRecognitionStats stats;
    PbnfcRecognitionResult result;
    int exit_code = 2;

    pbnfc_diagnostic_context_init(&diagnostics, stderr);

    (void)pthread_self();

    if (parse_options(argc, argv, &options, &diagnostics) != 0) {
        return 2;
    }

    if (!read_file(options.grammar_path,
                   "unable to read grammar file",
                   &grammar_source,
                   &grammar_length,
                   &diagnostics)) {
        goto cleanup;
    }
    if (!pbnfc_grammar_parse(grammar_source,
                             grammar_length,
                             &diagnostics,
                             &grammar) ||
        !pbnfc_grammar_validate(grammar, &diagnostics)) {
        goto cleanup;
    }
    if (!read_file(options.input_path,
                   "unable to read input file",
                   &input_source,
                   &input_length,
                   &diagnostics) ||
        !lex_input(input_source,
                   input_length,
                   &diagnostics,
                   &tokens,
                   &token_count)) {
        goto cleanup;
    }

    result = pbnfc_recognize_parallel_with_diagnostics(grammar,
                                                       tokens,
                                                       token_count,
                                                       options.start_name,
                                                       &diagnostics,
                                                       &stats);
    if (result == PBNFC_RECOGNITION_REJECTED) {
        exit_code = 1;
        goto cleanup;
    }
    if (result != PBNFC_RECOGNITION_ACCEPTED) {
        (void)pbnfc_diagnostic_emit(&diagnostics,
                                    "parallel recognizer failed",
                                    NULL);
        goto cleanup;
    }
    (void)fprintf(stdout, "ACCEPT tokens=%zu", token_count);
    if (options.have_stats) {
        print_stats(&stats);
    }
    (void)fputc('\n', stdout);
    exit_code = 0;

cleanup:
    free(tokens);
    pbnfc_grammar_free(grammar);
    free(input_source);
    free(grammar_source);
    return exit_code;
}
