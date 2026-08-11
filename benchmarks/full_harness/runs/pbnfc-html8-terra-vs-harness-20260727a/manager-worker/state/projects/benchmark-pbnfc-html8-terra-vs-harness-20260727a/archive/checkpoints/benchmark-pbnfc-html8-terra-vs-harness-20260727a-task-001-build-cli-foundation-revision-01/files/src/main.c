#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
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

static int command_line_error(const char *detail)
{
    (void)fprintf(stderr, "GRAMMAR_ERROR %s\n", detail);
    return 2;
}

static bool is_option(const char *argument)
{
    return argument[0] == '-' && argument[1] == '-';
}

static int parse_options(int argc, char **argv, CliOptions *options)
{
    int index;

    for (index = 1; index < argc; ++index) {
        const char *argument = argv[index];

        if (strcmp(argument, "--grammar") == 0) {
            if (options->have_grammar) {
                return command_line_error("duplicate option --grammar");
            }
            if (index + 1 >= argc || is_option(argv[index + 1])) {
                return command_line_error("missing value for --grammar");
            }
            options->grammar_path = argv[++index];
            options->have_grammar = true;
        } else if (strcmp(argument, "--input") == 0) {
            if (options->have_input) {
                return command_line_error("duplicate option --input");
            }
            if (index + 1 >= argc || is_option(argv[index + 1])) {
                return command_line_error("missing value for --input");
            }
            options->input_path = argv[++index];
            options->have_input = true;
        } else if (strcmp(argument, "--start") == 0) {
            if (options->have_start) {
                return command_line_error("duplicate option --start");
            }
            if (index + 1 >= argc || is_option(argv[index + 1])) {
                return command_line_error("missing value for --start");
            }
            options->start_name = argv[++index];
            options->have_start = true;
        } else if (strcmp(argument, "--stats") == 0) {
            if (options->have_stats) {
                return command_line_error("duplicate option --stats");
            }
            options->have_stats = true;
        } else if (is_option(argument)) {
            return command_line_error("unknown option");
        } else {
            return command_line_error("unexpected positional argument");
        }
    }

    if (!options->have_grammar) {
        return command_line_error("missing required option --grammar");
    }
    if (!options->have_input) {
        return command_line_error("missing required option --input");
    }

    return 0;
}

int main(int argc, char **argv)
{
    CliOptions options = {0};

    (void)pthread_self();

    if (parse_options(argc, argv, &options) != 0) {
        return 2;
    }

    (void)options;
    return command_line_error("grammar recognition is not implemented");
}
