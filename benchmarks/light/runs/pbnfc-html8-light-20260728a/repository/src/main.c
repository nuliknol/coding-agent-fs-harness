#include "diagnostics.h"
#include "grammar.h"
#include "markup.h"
#include "recognizer.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_file(const char *path, char **data, size_t *length)
{
    FILE *file = fopen(path, "rb");
    long size;
    size_t got;
    char *buffer;
    if (file == NULL)
        return -1;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return -1;
    }
    size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return -1;
    }
    buffer = (char *)malloc((size_t)size + 1);
    if (buffer == NULL) {
        fclose(file);
        return -1;
    }
    got = fread(buffer, 1, (size_t)size, file);
    fclose(file);
    if (got != (size_t)size) {
        free(buffer);
        return -1;
    }
    buffer[got] = '\0';
    *data = buffer;
    *length = got;
    return 0;
}

static void print_grammar_error(const char *what, const Diagnostic *diagnostic)
{
    if (diagnostic->present)
        (void)fprintf(stdout, "GRAMMAR_ERROR %s offset=%zu line=%zu column=%zu %s\n",
                      what, diagnostic->loc.offset, diagnostic->loc.line,
                      diagnostic->loc.column, diagnostic->message);
    else
        (void)fprintf(stdout, "GRAMMAR_ERROR %s\n", what);
}

static Location end_location(const char *source, size_t length)
{
    size_t i;
    Location loc = {length, 1, 1};
    for (i = 0; i < length; i++) {
        if (source[i] == '\n') {
            loc.line++;
            loc.column = 1;
        } else {
            loc.column++;
        }
    }
    return loc;
}

int main(int argc, char **argv)
{
    const char *grammar_path = NULL;
    const char *input_path = NULL;
    const char *start_name = NULL;
    int stats = 0;
    char *grammar_source = NULL;
    char *input_source = NULL;
    size_t grammar_length = 0;
    size_t input_length = 0;
    Grammar grammar;
    Markup markup;
    Diagnostic diagnostic;
    Recognition recognition;
    int i;
    int status;
    memset(&diagnostic, 0, sizeof(diagnostic));
    if (argc < 5) {
        print_grammar_error("usage: bin/pbnfc --grammar PATH --input PATH [--start NAME] [--stats]", &diagnostic);
        return 2;
    }
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--grammar") == 0 && i + 1 < argc)
            grammar_path = argv[++i];
        else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc)
            input_path = argv[++i];
        else if (strcmp(argv[i], "--start") == 0 && i + 1 < argc)
            start_name = argv[++i];
        else if (strcmp(argv[i], "--stats") == 0)
            stats = 1;
        else {
            print_grammar_error("invalid command line", &diagnostic);
            return 2;
        }
    }
    if (grammar_path == NULL || input_path == NULL) {
        print_grammar_error("--grammar and --input are required", &diagnostic);
        return 2;
    }
    if (read_file(grammar_path, &grammar_source, &grammar_length) != 0) {
        (void)fprintf(stdout, "GRAMMAR_ERROR cannot read grammar: ");
        diagnostic_print_escaped(stdout, grammar_path);
        (void)fputc('\n', stdout);
        return 2;
    }
    if (read_file(input_path, &input_source, &input_length) != 0) {
        free(grammar_source);
        (void)fprintf(stdout, "GRAMMAR_ERROR cannot read input: ");
        diagnostic_print_escaped(stdout, input_path);
        (void)fputc('\n', stdout);
        return 2;
    }
    if (grammar_parse(grammar_source, grammar_length, &grammar, &diagnostic) != 0) {
        print_grammar_error("grammar", &diagnostic);
        free(grammar_source);
        free(input_source);
        return 2;
    }
    if (start_name != NULL && grammar_set_start(&grammar, start_name, &diagnostic) != 0) {
        print_grammar_error("grammar", &diagnostic);
        grammar_free(&grammar);
        free(grammar_source);
        free(input_source);
        return 2;
    }
    if (markup_lex(input_source, input_length, &markup, &diagnostic) != 0) {
        print_grammar_error("markup", &diagnostic);
        grammar_free(&grammar);
        free(grammar_source);
        free(input_source);
        return 2;
    }
    status = recognize(&grammar, &markup, &recognition);
    if (status != 0) {
        (void)fprintf(stdout, "GRAMMAR_ERROR recognizer failure\n");
        markup_free(&markup);
        grammar_free(&grammar);
        free(grammar_source);
        free(input_source);
        return 2;
    }
    if (recognition.accepted) {
        (void)fprintf(stdout, "ACCEPT tokens=%zu", markup.count);
        if (stats) {
            (void)fprintf(stdout, " workers=8 active_workers=8 rounds=%zu tasks=", recognition.rounds);
            for (i = 0; i < 8; i++)
                (void)fprintf(stdout, "%s%zu", i == 0 ? "" : ",", recognition.tasks[i]);
        }
        (void)fprintf(stdout, "\n");
        status = 0;
    } else {
        Location location;
        if (recognition.error_position < markup.count)
            location = markup.tokens[recognition.error_position].loc;
        else
            location = end_location(input_source, input_length);
        (void)fprintf(stdout, "REJECT offset=%zu line=%zu column=%zu expected=%s\n",
                      location.offset, location.line, location.column, recognition.expected);
        status = 1;
    }
    markup_free(&markup);
    grammar_free(&grammar);
    free(grammar_source);
    free(input_source);
    return status;
}
