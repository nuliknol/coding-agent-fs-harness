#include "diagnostics.h"

static void write_detail(FILE *stream, const char *detail)
{
    const char *cursor = detail;

    if (cursor == NULL || *cursor == '\0') {
        (void)fputs("unspecified diagnostic", stream);
        return;
    }

    while (*cursor != '\0') {
        if (*cursor == '\n' || *cursor == '\r') {
            (void)fputc(' ', stream);
        } else {
            (void)fputc((unsigned char)*cursor, stream);
        }
        ++cursor;
    }
}

void pbnfc_diagnostic_context_init(PbnfcDiagnosticContext *context,
                                   FILE *stream)
{
    if (context != NULL) {
        context->stream = stream;
    }
}

bool pbnfc_diagnostic_emit(const PbnfcDiagnosticContext *context,
                           const char *detail,
                           const PbnfcLocation *location)
{
    FILE *stream;

    if (context == NULL || context->stream == NULL) {
        return false;
    }

    stream = context->stream;
    if (fputs("GRAMMAR_ERROR ", stream) == EOF) {
        return false;
    }
    write_detail(stream, detail);
    if (location != NULL) {
        if (fprintf(stream,
                    " offset=%zu line=%zu column=%zu",
                    location->byte_offset,
                    location->line,
                    location->column) < 0) {
            return false;
        }
    }
    if (fputc('\n', stream) == EOF) {
        return false;
    }

    return true;
}

bool pbnfc_rejection_emit(const PbnfcDiagnosticContext *context,
                          const char *expected,
                          const PbnfcLocation *location)
{
    FILE *stream;

    if (context == NULL || context->stream == NULL || location == NULL) {
        return false;
    }

    stream = context->stream;
    if (fprintf(stream,
                "REJECT offset=%zu line=%zu column=%zu expected=",
                location->byte_offset,
                location->line,
                location->column) < 0) {
        return false;
    }
    write_detail(stream, expected);
    if (fputc('\n', stream) == EOF) {
        return false;
    }
    return true;
}
