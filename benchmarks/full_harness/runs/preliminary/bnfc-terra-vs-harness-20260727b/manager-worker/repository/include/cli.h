#ifndef BNFC_CLI_H
#define BNFC_CLI_H

#include <stddef.h>

typedef struct {
    char *grammar_path;
    char *input;
    char *start_name;
} CliOptions;

/* Returns 0 for a valid command line and -1 for a command-line error. */
int cli_parse(int argc, char *const argv[], CliOptions *options,
              char *error, size_t error_size);

void cli_options_destroy(CliOptions *options);

#endif
