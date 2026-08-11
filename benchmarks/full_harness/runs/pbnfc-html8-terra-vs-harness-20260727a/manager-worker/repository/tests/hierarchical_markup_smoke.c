#define _POSIX_C_SOURCE 200809L

#include "worker_pool.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "hierarchical markup smoke: %s\n", detail);
    return 1;
}

static int write_fixture(const char *path, const char *contents)
{
    FILE *stream = fopen(path, "wb");

    if (stream == NULL || fputs(contents, stream) == EOF || fclose(stream) != 0) {
        if (stream != NULL) {
            (void)fclose(stream);
        }
        return 1;
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
    static const char input_source[] =
        "<a href='url'> link text </a>"
        "<div id=\"root\"><p>Hello <strong>world</strong></p>"
        "<img src='x.png'/></div>";
    char grammar_path[128];
    char input_path[128];
    char command[384];
    char output[512];
    FILE *stream;
    size_t tokens;
    size_t workers;
    size_t active_workers;
    size_t rounds;
    size_t tasks[PBNFC_WORKER_POOL_SIZE];
    char trailing;
    int matched;
    int status;
    size_t worker_index;

    if (snprintf(grammar_path,
                 sizeof(grammar_path),
                 "/tmp/pbnfc-hierarchical-%ld.grammar",
                 (long)getpid()) < 0 ||
        snprintf(input_path,
                 sizeof(input_path),
                 "/tmp/pbnfc-hierarchical-%ld.input",
                 (long)getpid()) < 0) {
        return fail("could not form temporary paths");
    }
    if (write_fixture(grammar_path, grammar_source) != 0 ||
        write_fixture(input_path, input_source) != 0) {
        (void)unlink(grammar_path);
        (void)unlink(input_path);
        return fail("could not write fixture files");
    }
    if (snprintf(command,
                 sizeof(command),
                 "./bin/pbnfc --grammar %s --input %s --stats",
                 grammar_path,
                 input_path) < 0) {
        (void)unlink(grammar_path);
        (void)unlink(input_path);
        return fail("could not form CLI command");
    }
    stream = popen(command, "r");
    if (stream == NULL || fgets(output, sizeof(output), stream) == NULL) {
        if (stream != NULL) {
            (void)pclose(stream);
        }
        (void)unlink(grammar_path);
        (void)unlink(input_path);
        return fail("CLI did not produce an acceptance line");
    }
    status = pclose(stream);
    (void)unlink(grammar_path);
    (void)unlink(input_path);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        return fail("nested document was not accepted");
    }
    matched = sscanf(output,
                     "ACCEPT tokens=%zu workers=%zu active_workers=%zu "
                     "rounds=%zu tasks=%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu%c",
                     &tokens,
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
    if (matched != 13 || trailing != '\n' || tokens != 44U ||
        workers != PBNFC_WORKER_POOL_SIZE ||
        active_workers != PBNFC_WORKER_POOL_SIZE || rounds == 0U) {
        return fail("acceptance line has the wrong format");
    }
    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        if (tasks[worker_index] == 0U) {
            return fail("a worker reported no hierarchical markup work");
        }
    }
    return 0;
}
