#include "cli.h"

#include <stdio.h>

int main(int argc, char *argv[])
{
    CliOptions options;
    char error[128];

    if (cli_parse(argc, argv, &options, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "GRAMMAR_ERROR %s\n", error);
        return 2;
    }

    /* Grammar loading and input recognition belong to later leaves. */
    cli_options_destroy(&options);
    return 0;
}
