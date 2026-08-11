#ifndef PBNFC_DIAGNOSTICS_H
#define PBNFC_DIAGNOSTICS_H

#include <stddef.h>
#include <stdio.h>

typedef struct {
    size_t offset;
    size_t line;
    size_t column;
} Location;

typedef struct {
    int present;
    Location loc;
    char message[256];
} Diagnostic;

void diagnostic_set(Diagnostic *d, Location loc, const char *message);
void diagnostic_setf(Diagnostic *d, Location loc, const char *format, const char *arg);
void diagnostic_print_escaped(FILE *stream, const char *text);

#endif
