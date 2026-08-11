#include "pbnfc.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

void error_set(Error *e, Location loc, const char *fmt, ...) {
    va_list ap;
    e->loc = loc;
    va_start(ap, fmt);
    (void)vsnprintf(e->message, sizeof(e->message), fmt, ap);
    va_end(ap);
}
