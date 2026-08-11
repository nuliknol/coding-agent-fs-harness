#define _POSIX_C_SOURCE 200809L

#include "worker_pool.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "hierarchical stress smoke: %s\n", detail);
    return 1;
}

static int write_fixture(const char *path, const char *contents)
{
    FILE *stream = fopen(path, "wb");

    if (stream == NULL) {
        return 1;
    }
    if (fputs(contents, stream) == EOF) {
        (void)fclose(stream);
        return 1;
    }
    return fclose(stream) == 0 ? 0 : 1;
}

static int write_stress_input(const char *path)
{
    static const char fragment[] =
        "<section id='root'><div class='outer'><a href='url'>"
        "<p>Hello <strong>world</strong><em>!</em></p>"
        "</a><ul class='list'><li data='one'><span>alpha</span>"
        "<img src='one.png'/></li><li data='two'><span>beta</span>"
        "<img src='two.png'/></li></ul></div></section>";
    FILE *stream = fopen(path, "wb");
    size_t repetition;

    if (stream == NULL) {
        return 1;
    }
    for (repetition = 0U; repetition < 10U; ++repetition) {
        if (fputs(fragment, stream) == EOF) {
            (void)fclose(stream);
            return 1;
        }
    }
    return fclose(stream) == 0 ? 0 : 1;
}

static int check_acceptance_line(const char *output,
                                 size_t *tokens_out,
                                 size_t tasks[PBNFC_WORKER_POOL_SIZE])
{
    size_t workers;
    size_t active_workers;
    size_t rounds;
    char trailing;
    int matched;
    size_t worker_index;

    matched = sscanf(output,
                     "ACCEPT tokens=%zu workers=%zu active_workers=%zu "
                     "rounds=%zu tasks=%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu%c",
                     tokens_out,
                     &workers,
                     &active_workers,
                     &rounds,
                     &tasks[0],
                     &tasks[1],
                     &tasks[2],
                     &tasks[3],
                     &tasks[4],
                     &tasks[5],
                     &tasks[6],
                     &tasks[7],
                     &trailing);
    if (matched != 13 || trailing != '\n' || *tokens_out <= 100U ||
        workers != PBNFC_WORKER_POOL_SIZE ||
        active_workers != PBNFC_WORKER_POOL_SIZE || rounds == 0U) {
        return 1;
    }
    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        if (tasks[worker_index] == 0U) {
            return 1;
        }
    }
    return 0;
}

int main(void)
{
    static const char grammar_source[] =
        "%start Document\n"
        "%token IDENT\n"
        "%token STRING\n"
        "%token TEXT\n"
        "Document ::= Nodes ;\n"
        "Nodes ::= Node Nodes | ;\n"
        "Node ::= Text | A | Div | Span | P | Section | Ul | Li | Strong | Em | Img ;\n"
        "Text ::= $TEXT ;\n"
        "Attributes ::= Attribute Attributes | ;\n"
        "Attribute ::= $IDENT '=' $STRING ;\n"
        "A ::= '<' 'a' Attributes '>' Nodes '<' '/' 'a' '>' ;\n"
        "Div ::= '<' 'div' Attributes '>' Nodes '<' '/' 'div' '>' ;\n"
        "Span ::= '<' 'span' Attributes '>' Nodes '<' '/' 'span' '>' ;\n"
        "P ::= '<' 'p' Attributes '>' Nodes '<' '/' 'p' '>' ;\n"
        "Section ::= '<' 'section' Attributes '>' Nodes '<' '/' 'section' '>' ;\n"
        "Ul ::= '<' 'ul' Attributes '>' Nodes '<' '/' 'ul' '>' ;\n"
        "Li ::= '<' 'li' Attributes '>' Nodes '<' '/' 'li' '>' ;\n"
        "Strong ::= '<' 'strong' Attributes '>' Nodes '<' '/' 'strong' '>' ;\n"
        "Em ::= '<' 'em' Attributes '>' Nodes '<' '/' 'em' '>' ;\n"
        "Img ::= '<' 'img' Attributes '/' '>' ;\n";
    char grammar_path[128];
    char input_path[128];
    char command[384];
    char output[1024];
    char expected_output[1024];
    FILE *stream;
    size_t tokens;
    size_t tasks[PBNFC_WORKER_POOL_SIZE];
    size_t repetition;
    int status;
    int have_expected = 0;

    if (snprintf(grammar_path,
                 sizeof(grammar_path),
                 "/tmp/pbnfc-hierarchical-stress-%ld.grammar",
                 (long)getpid()) < 0 ||
        snprintf(input_path,
                 sizeof(input_path),
                 "/tmp/pbnfc-hierarchical-stress-%ld.input",
                 (long)getpid()) < 0) {
        return fail("could not form temporary paths");
    }
    if (write_fixture(grammar_path, grammar_source) != 0 ||
        write_stress_input(input_path) != 0) {
        (void)unlink(grammar_path);
        (void)unlink(input_path);
        return fail("could not write fixture files");
    }
    if (snprintf(command,
                 sizeof(command),
                 "./bin/pbnfc --grammar %s --input %s --stats 2>&1",
                 grammar_path,
                 input_path) < 0) {
        (void)unlink(grammar_path);
        (void)unlink(input_path);
        return fail("could not form CLI command");
    }
    for (repetition = 0U; repetition < 8U; ++repetition) {
        stream = popen(command, "r");
        if (stream == NULL || fgets(output, sizeof(output), stream) == NULL) {
            if (stream != NULL) {
                (void)pclose(stream);
            }
            (void)unlink(grammar_path);
            (void)unlink(input_path);
            return fail("CLI did not produce an acceptance line");
        }
        if (fgets(expected_output, sizeof(expected_output), stream) != NULL) {
            (void)pclose(stream);
            (void)unlink(grammar_path);
            (void)unlink(input_path);
            return fail("CLI emitted more than one line");
        }
        status = pclose(stream);
        if (!WIFEXITED(status) || WEXITSTATUS(status) != 0 ||
            check_acceptance_line(output, &tokens, tasks) != 0) {
            (void)unlink(grammar_path);
            (void)unlink(input_path);
            return fail("stress document was not accepted with full worker work");
        }
        if (!have_expected) {
            (void)strcpy(expected_output, output);
            have_expected = 1;
        } else if (strcmp(expected_output, output) != 0) {
            (void)unlink(grammar_path);
            (void)unlink(input_path);
            return fail("repeated acceptance output was not deterministic");
        }
    }
    (void)unlink(grammar_path);
    (void)unlink(input_path);
    return 0;
}
