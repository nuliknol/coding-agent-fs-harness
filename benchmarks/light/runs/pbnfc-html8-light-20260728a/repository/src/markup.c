#include "markup.h"

#include <stdlib.h>
#include <string.h>

static char *copy_text(const char *text, size_t length)
{
    char *result = (char *)malloc(length + 1);
    if (result != NULL) {
        memcpy(result, text, length);
        result[length] = '\0';
    }
    return result;
}

static int grow_tokens(Markup *markup)
{
    size_t capacity = markup->capacity == 0 ? 16 : markup->capacity * 2;
    MarkupToken *grown;
    if (markup->capacity >= markup->count + 1)
        return 0;
    if (capacity < markup->count + 1)
        return -1;
    grown = (MarkupToken *)realloc(markup->tokens, capacity * sizeof(*grown));
    if (grown == NULL)
        return -1;
    markup->tokens = grown;
    markup->capacity = capacity;
    return 0;
}

static int add_token(Markup *markup, MarkupKind kind, const char *text, size_t length, Location loc)
{
    MarkupToken *token;
    if (grow_tokens(markup) != 0)
        return -1;
    token = &markup->tokens[markup->count++];
    token->kind = kind;
    token->lexeme = copy_text(text, length);
    token->loc = loc;
    if (token->lexeme == NULL) {
        markup->count--;
        return -1;
    }
    return 0;
}

static void move_location(Location *loc, char c, size_t *offset)
{
    (*offset)++;
    if (c == '\n') {
        loc->line++;
        loc->column = 1;
    } else {
        loc->column++;
    }
}

static int ascii_space(char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static int identifier_start(char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == ':';
}

static int identifier_part(char c)
{
    return identifier_start(c) || (c >= '0' && c <= '9') || c == '.' || c == '-';
}

int markup_lex(const char *source, size_t length, Markup *markup, Diagnostic *diagnostic)
{
    size_t offset = 0;
    Location loc = {0, 1, 1};
    int in_tag = 0;
    memset(markup, 0, sizeof(*markup));
    memset(diagnostic, 0, sizeof(*diagnostic));
    while (offset < length) {
        char c = source[offset];
        Location start = loc;
        size_t begin;
        if ((unsigned char)c < 0x20 && !ascii_space(c)) {
            diagnostic_set(diagnostic, loc, "invalid byte in markup");
            markup_free(markup);
            return -1;
        }
        if ((unsigned char)c >= 0x7f) {
            diagnostic_set(diagnostic, loc, "invalid byte in markup");
            markup_free(markup);
            return -1;
        }
        if (!in_tag) {
            if (c == '<') {
                if (add_token(markup, MARKUP_LITERAL, "<", 1, start) != 0)
                    goto out_of_memory;
                move_location(&loc, c, &offset);
                in_tag = 1;
            } else {
                begin = offset;
                {
                    int all_whitespace = 1;
                    while (offset < length && source[offset] != '<') {
                    c = source[offset];
                    if (((unsigned char)c < 0x20 && !ascii_space(c)) || (unsigned char)c >= 0x7f) {
                        diagnostic_set(diagnostic, loc, "invalid byte in markup");
                        markup_free(markup);
                        return -1;
                    }
                    if (!ascii_space(c))
                        all_whitespace = 0;
                    move_location(&loc, c, &offset);
                    }
                    if (!all_whitespace && add_token(markup, MARKUP_TEXT, source + begin,
                                                     offset - begin, start) != 0)
                        goto out_of_memory;
                }
            }
            continue;
        }
        if (ascii_space(c)) {
            move_location(&loc, c, &offset);
            continue;
        }
        if (c == '<' || c == '>' || c == '/' || c == '=') {
            if (add_token(markup, MARKUP_LITERAL, &c, 1, start) != 0)
                goto out_of_memory;
            move_location(&loc, c, &offset);
            if (c == '>')
                in_tag = 0;
            continue;
        }
        if (c == '\'' || c == '"') {
            char quote = c;
            size_t out = 0;
            char *value = (char *)malloc(1);
            if (value == NULL)
                goto out_of_memory;
            value[0] = '\0';
            move_location(&loc, c, &offset);
            while (offset < length && source[offset] != quote) {
                c = source[offset];
                if (c == '\\') {
                    move_location(&loc, c, &offset);
                    if (offset == length || (source[offset] != quote && source[offset] != '\\')) {
                        free(value);
                        diagnostic_set(diagnostic, loc, "invalid string escape in markup");
                        markup_free(markup);
                        return -1;
                    }
                    c = source[offset];
                }
                if ((unsigned char)c < 0x20 || (unsigned char)c >= 0x7f) {
                    free(value);
                    diagnostic_set(diagnostic, loc, "invalid byte in markup string");
                    markup_free(markup);
                    return -1;
                }
                {
                    char *grown = (char *)realloc(value, out + 2);
                    if (grown == NULL) {
                        free(value);
                        goto out_of_memory;
                    }
                    value = grown;
                }
                value[out++] = c;
                value[out] = '\0';
                move_location(&loc, c, &offset);
            }
            if (offset == length) {
                free(value);
                diagnostic_set(diagnostic, start, "unterminated markup string");
                markup_free(markup);
                return -1;
            }
            move_location(&loc, quote, &offset);
            if (grow_tokens(markup) != 0) {
                free(value);
                goto out_of_memory;
            }
            markup->tokens[markup->count++] = (MarkupToken){MARKUP_STRING, value, start};
            continue;
        }
        if (identifier_start(c)) {
            begin = offset;
            move_location(&loc, c, &offset);
            while (offset < length && identifier_part(source[offset]))
                move_location(&loc, source[offset], &offset);
            if (add_token(markup, MARKUP_IDENT, source + begin, offset - begin, start) != 0)
                goto out_of_memory;
            continue;
        }
        diagnostic_set(diagnostic, loc, "invalid character in markup tag");
        markup_free(markup);
        return -1;
    }
    if (in_tag) {
        diagnostic_set(diagnostic, loc, "unterminated markup tag");
        markup_free(markup);
        return -1;
    }
    return 0;

out_of_memory:
    diagnostic_set(diagnostic, loc, "out of memory");
    markup_free(markup);
    return -1;
}

void markup_free(Markup *markup)
{
    size_t i;
    for (i = 0; i < markup->count; i++)
        free(markup->tokens[i].lexeme);
    free(markup->tokens);
    memset(markup, 0, sizeof(*markup));
}
