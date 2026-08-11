#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "hierarchical rejection smoke: %s\n", detail);
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

static int check_rejection(const char *grammar_path,
                           const char *input_path,
                           size_t expected_offset,
                           size_t expected_line,
                           size_t expected_column)
{
    char command[512];
    char output[512];
    char expected[448];
    char trailing;
    FILE *stream;
    size_t offset;
    size_t line;
    size_t column;
    int matched;
    int status;

    if (snprintf(command,
                 sizeof(command),
                 "./bin/pbnfc --grammar %s --input %s 2>&1",
                 grammar_path,
                 input_path) < 0) {
        return fail("could not form CLI command");
    }
    stream = popen(command, "r");
    if (stream == NULL || fgets(output, sizeof(output), stream) == NULL) {
        if (stream != NULL) {
            (void)pclose(stream);
        }
        return fail("CLI did not produce a rejection line");
    }
    matched = sscanf(output,
                     "REJECT offset=%zu line=%zu column=%zu expected=%447[^\n]%c",
                     &offset,
                     &line,
                     &column,
                     expected,
                     &trailing);
    if (matched != 5 || trailing != '\n' || expected[0] == '\0' ||
        offset != expected_offset || line != expected_line ||
        column != expected_column) {
        (void)pclose(stream);
        return fail("rejection line has the wrong diagnostics");
    }
    if (fgets(output, sizeof(output), stream) != NULL) {
        (void)pclose(stream);
        return fail("CLI emitted more than one diagnostic line");
    }
    status = pclose(stream);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 1) {
        return fail("CLI did not exit with rejection status 1");
    }
    return 0;
}

int main(void)
{
    static const char grammar_source[] =
        "%start Document\n"
        "%token TEXT\n"
        "Document ::= Nodes ;\n"
        "Nodes ::= Node Nodes | ;\n"
        "Node ::= A | Div | Text ;\n"
        "Text ::= $TEXT ;\n"
        "A ::= '<' 'a' '>' Nodes '<' '/' 'a' '>' ;\n"
        "Div ::= '<' 'div' '>' Nodes '<' '/' 'div' '>' ;\n";
    static const char mismatched_input[] = "<a>ok\n</div>";
    static const char unknown_input[] = "<aside>ok</aside>";
    char grammar_path[128];
    char mismatched_path[128];
    char unknown_path[128];
    int result = 1;

    if (snprintf(grammar_path,
                 sizeof(grammar_path),
                 "/tmp/pbnfc-hierarchical-rejection-%ld.grammar",
                 (long)getpid()) < 0 ||
        snprintf(mismatched_path,
                 sizeof(mismatched_path),
                 "/tmp/pbnfc-hierarchical-rejection-%ld-mismatch.input",
                 (long)getpid()) < 0 ||
        snprintf(unknown_path,
                 sizeof(unknown_path),
                 "/tmp/pbnfc-hierarchical-rejection-%ld-unknown.input",
                 (long)getpid()) < 0) {
        return fail("could not form temporary paths");
    }
    if (write_fixture(grammar_path, grammar_source) != 0 ||
        write_fixture(mismatched_path, mismatched_input) != 0 ||
        write_fixture(unknown_path, unknown_input) != 0) {
        result = fail("could not write fixture files");
        goto cleanup;
    }
    if (check_rejection(grammar_path, mismatched_path, 8U, 2U, 3U) != 0 ||
        check_rejection(grammar_path, unknown_path, 1U, 1U, 2U) != 0) {
        goto cleanup;
    }
    result = 0;

cleanup:
    (void)unlink(grammar_path);
    (void)unlink(mismatched_path);
    (void)unlink(unknown_path);
    return result;
}
