#include "cli.h"
#include "lexer.h"

#include <stdio.h>

int main(int argc, char *argv[])
{
    CliOptions options;
    GrammarTokenList tokens;
    char error[128];

    if (cli_parse(argc, argv, &options, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "GRAMMAR_ERROR %s\n", error);
        return 2;
    }

    if (grammar_lex_file(options.grammar_path, &tokens, error, sizeof(error)) !=
        0) {
        (void)fprintf(stderr, "GRAMMAR_ERROR %s\n", error);
        cli_options_destroy(&options);
        return 2;
    }

    grammar_token_list_destroy(&tokens);
    cli_options_destroy(&options);
    return 0;
}
