#include "cli.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void set_error(char *error, size_t error_size, const char *detail)
{
    if (error_size == 0U) {
        return;
    }
    (void)snprintf(error, error_size, "%s", detail);
}

static char *copy_string(const char *value)
{
    size_t length = strlen(value);
    char *copy = (char *)malloc(length + 1U);

    if (copy != NULL) {
        (void)memcpy(copy, value, length + 1U);
    }
    return copy;
}

static int is_option_name(const char *argument)
{
    return argument[0] == '-';
}

static int take_value(int argc, char *const argv[], int *index,
                      const char **value, char *error, size_t error_size,
                      const char *option)
{
    int next = *index + 1;

    if (next >= argc || is_option_name(argv[next])) {
        (void)snprintf(error, error_size, "missing value for %s", option);
        return -1;
    }
    *index = next;
    *value = argv[next];
    return 0;
}

int cli_parse(int argc, char *const argv[], CliOptions *options,
              char *error, size_t error_size)
{
    int index;

    if (options == NULL || error == NULL || error_size == 0U) {
        return -1;
    }
    options->grammar_path = NULL;
    options->input = NULL;
    options->start_name = NULL;
    set_error(error, error_size, "invalid command-line arguments");

    for (index = 1; index < argc; ++index) {
        const char *value;
        char **destination;
        const char *option = argv[index];

        if (strcmp(option, "--grammar") == 0) {
            destination = &options->grammar_path;
        } else if (strcmp(option, "--input") == 0) {
            destination = &options->input;
        } else if (strcmp(option, "--start") == 0) {
            destination = &options->start_name;
        } else if (is_option_name(option)) {
            set_error(error, error_size, "unknown command-line option");
            cli_options_destroy(options);
            return -1;
        } else {
            set_error(error, error_size, "unexpected positional argument");
            cli_options_destroy(options);
            return -1;
        }

        if (*destination != NULL) {
            (void)snprintf(error, error_size, "duplicate option %s", option);
            cli_options_destroy(options);
            return -1;
        }
        if (take_value(argc, argv, &index, &value, error, error_size,
                       option) != 0) {
            cli_options_destroy(options);
            return -1;
        }
        *destination = copy_string(value);
        if (*destination == NULL) {
            set_error(error, error_size, "out of memory");
            cli_options_destroy(options);
            return -1;
        }
    }

    if (options->grammar_path == NULL) {
        set_error(error, error_size, "missing required option --grammar");
        cli_options_destroy(options);
        return -1;
    }
    if (options->input == NULL) {
        set_error(error, error_size, "missing required option --input");
        cli_options_destroy(options);
        return -1;
    }
    return 0;
}

void cli_options_destroy(CliOptions *options)
{
    if (options == NULL) {
        return;
    }
    free(options->grammar_path);
    free(options->input);
    free(options->start_name);
    options->grammar_path = NULL;
    options->input = NULL;
    options->start_name = NULL;
}
