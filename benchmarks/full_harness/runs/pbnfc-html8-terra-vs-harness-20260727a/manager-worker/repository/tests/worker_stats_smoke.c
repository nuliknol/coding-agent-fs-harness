#define _POSIX_C_SOURCE 200809L

#include "worker_pool.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "worker statistics smoke: %s\n", detail);
    return 1;
}

int main(void)
{
    static const char grammar_source[] =
        "%start Document\n"
        "%token TEXT\n"
        "Document ::= $TEXT | $TEXT | $TEXT | $TEXT | $TEXT | $TEXT | "
        "$TEXT | $TEXT ;\n";
    static const char input_source[] = "parallel scan\n";
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
                 "/tmp/pbnfc-worker-stats-%ld.grammar",
                 (long)getpid()) < 0 ||
        snprintf(input_path,
                 sizeof(input_path),
                 "/tmp/pbnfc-worker-stats-%ld.input",
                 (long)getpid()) < 0) {
        return fail("could not form temporary paths");
    }
    stream = fopen(grammar_path, "wb");
    if (stream == NULL ||
        fputs(grammar_source, stream) == EOF ||
        fclose(stream) != 0) {
        if (stream != NULL) {
            (void)fclose(stream);
        }
        (void)unlink(grammar_path);
        return fail("could not write grammar fixture");
    }
    stream = fopen(input_path, "wb");
    if (stream == NULL ||
        fputs(input_source, stream) == EOF ||
        fclose(stream) != 0) {
        if (stream != NULL) {
            (void)fclose(stream);
        }
        (void)unlink(grammar_path);
        (void)unlink(input_path);
        return fail("could not write input fixture");
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
        return fail("CLI did not produce statistics");
    }
    status = pclose(stream);
    (void)unlink(grammar_path);
    (void)unlink(input_path);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        return fail("CLI recognition failed");
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
    if (matched != 13 || trailing != '\n' || tokens != 1U ||
        workers != PBNFC_WORKER_POOL_SIZE ||
        active_workers != PBNFC_WORKER_POOL_SIZE || rounds == 0U) {
        return fail("statistics line has the wrong format");
    }
    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        if (tasks[worker_index] == 0U) {
            return fail("a worker reported no task");
        }
    }
    return 0;
}
