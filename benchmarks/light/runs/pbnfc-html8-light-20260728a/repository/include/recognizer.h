#ifndef PBNFC_RECOGNIZER_H
#define PBNFC_RECOGNIZER_H

#include <stddef.h>
#include "grammar.h"
#include "markup.h"
#include "pool.h"

typedef struct {
    int accepted;
    size_t error_position;
    char expected[160];
    size_t rounds;
    size_t tasks[8];
} Recognition;

int recognize(const Grammar *grammar, const Markup *markup, Recognition *result);

#endif
