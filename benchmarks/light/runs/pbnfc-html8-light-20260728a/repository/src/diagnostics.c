#include "diagnostics.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static void append_escaped(char *destination, size_t capacity, const char *source)
{
    size_t used = 0;
    while (*source != '\0' && used + 1 < capacity) {
        unsigned char c = (unsigned char)*source++;
        const char *escape = NULL;
        char hex[5];
        if (c == '\n') escape = "\\n";
        else if (c == '\r') escape = "\\r";
        else if (c == '\t') escape = "\\t";
        else if (c == '\\') escape = "\\\\";
        else if (c < 0x20 || c >= 0x7f) {
            (void)snprintf(hex, sizeof(hex), "\\x%02X", (unsigned)c);
            escape = hex;
        }
        if (escape != NULL) {
            while (*escape != '\0' && used + 1 < capacity)
                destination[used++] = *escape++;
        } else {
            destination[used++] = (char)c;
        }
    }
    destination[used] = '\0';
}

void diagnostic_set(Diagnostic *d, Location loc, const char *message)
{
    d->present = 1;
    d->loc = loc;
    append_escaped(d->message, sizeof(d->message), message);
}

void diagnostic_setf(Diagnostic *d, Location loc, const char *format, const char *arg)
{
    char formatted[256];
    d->present = 1;
    d->loc = loc;
    (void)snprintf(formatted, sizeof(formatted), format, arg);
    append_escaped(d->message, sizeof(d->message), formatted);
}

void diagnostic_print_escaped(FILE *stream, const char *text)
{
    while (*text != '\0') {
        unsigned char c = (unsigned char)*text++;
        if (c == '\n') fputs("\\n", stream);
        else if (c == '\r') fputs("\\r", stream);
        else if (c == '\t') fputs("\\t", stream);
        else if (c == '\\') fputs("\\\\", stream);
        else if (c < 0x20 || c >= 0x7f) (void)fprintf(stream, "\\x%02X", (unsigned)c);
        else (void)fputc((int)c, stream);
    }
}
