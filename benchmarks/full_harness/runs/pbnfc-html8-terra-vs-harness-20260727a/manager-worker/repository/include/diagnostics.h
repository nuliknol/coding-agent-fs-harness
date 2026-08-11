#ifndef PBNFC_DIAGNOSTICS_H
#define PBNFC_DIAGNOSTICS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

typedef struct {
    size_t byte_offset;
    size_t line;
    size_t column;
} PbnfcLocation;

typedef struct {
    FILE *stream;
} PbnfcDiagnosticContext;

void pbnfc_diagnostic_context_init(PbnfcDiagnosticContext *context,
                                   FILE *stream);

bool pbnfc_diagnostic_emit(const PbnfcDiagnosticContext *context,
                           const char *detail,
                           const PbnfcLocation *location);

/* Emit a syntactically valid input rejection with parser expectations. */
bool pbnfc_rejection_emit(const PbnfcDiagnosticContext *context,
                          const char *expected,
                          const PbnfcLocation *location);

#endif
