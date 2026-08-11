#include "lexer.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *data;
    size_t length;
    size_t capacity;
} StringBuilder;

static void set_error(char *error, size_t error_size, const char *detail)
{
    if (error_size != 0U) {
        (void)snprintf(error, error_size, "%s", detail);
    }
}

static void set_line_error(char *error, size_t error_size, size_t line,
                           const char *detail)
{
    if (error_size != 0U) {
        (void)snprintf(error, error_size, "line=%zu %s", line, detail);
    }
}

static int is_ascii_space(int character)
{
    return character == ' ' || character == '\t' || character == '\n' ||
           character == '\r' || character == '\f' || character == '\v';
}

static int is_identifier_start(int character)
{
    return (character >= 'A' && character <= 'Z') ||
           (character >= 'a' && character <= 'z') || character == '_';
}

static int is_identifier_part(int character)
{
    return is_identifier_start(character) ||
           (character >= '0' && character <= '9');
}

static char *copy_range(const char *data, size_t length)
{
    char *copy = (char *)malloc(length + 1U);

    if (copy != NULL) {
        if (length != 0U) {
            (void)memcpy(copy, data, length);
        }
        copy[length] = '\0';
    }
    return copy;
}

static int string_builder_append(StringBuilder *builder, int character)
{
    char *new_data;
    size_t new_capacity;

    if (builder->length + 1U >= builder->capacity) {
        new_capacity = builder->capacity == 0U ? 16U : builder->capacity * 2U;
        if (new_capacity <= builder->capacity) {
            return -1;
        }
        new_data = (char *)realloc(builder->data, new_capacity);
        if (new_data == NULL) {
            return -1;
        }
        builder->data = new_data;
        builder->capacity = new_capacity;
    }
    builder->data[builder->length] = (char)character;
    builder->length += 1U;
    return 0;
}

static char *string_builder_finish(StringBuilder *builder)
{
    char *value = builder->data;

    if (value == NULL) {
        value = copy_range("", 0U);
    } else {
        value[builder->length] = '\0';
    }
    builder->data = NULL;
    builder->length = 0U;
    builder->capacity = 0U;
    return value;
}

static int append_token(GrammarTokenList *tokens, GrammarTokenType type,
                        char *value, size_t line)
{
    GrammarToken *new_items;
    size_t new_count;

    new_count = tokens->count + 1U;
    if (new_count <= tokens->count ||
        new_count > ((size_t)-1) / sizeof(*tokens->items)) {
        return -1;
    }
    new_items = (GrammarToken *)realloc(
        tokens->items, new_count * sizeof(*tokens->items));
    if (new_items == NULL) {
        return -1;
    }
    tokens->items = new_items;
    tokens->items[tokens->count].type = type;
    tokens->items[tokens->count].value = value;
    tokens->items[tokens->count].line = line;
    tokens->count = new_count;
    return 0;
}

static int lex_identifier(FILE *stream, int first, size_t line,
                          GrammarTokenList *tokens, char *error,
                          size_t error_size)
{
    char *value;
    size_t length = 0U;
    size_t capacity = 16U;
    int character;

    value = (char *)malloc(capacity);
    if (value == NULL) {
        set_error(error, error_size, "out of memory");
        return -1;
    }
    value[length] = (char)first;
    length += 1U;
    for (;;) {
        character = fgetc(stream);
        if (character == EOF || !is_identifier_part(character)) {
            break;
        }
        if (length + 1U >= capacity) {
            char *new_value;
            size_t new_capacity = capacity * 2U;

            if (new_capacity <= capacity) {
                free(value);
                set_error(error, error_size, "identifier is too long");
                return -1;
            }
            new_value = (char *)realloc(value, new_capacity);
            if (new_value == NULL) {
                free(value);
                set_error(error, error_size, "out of memory");
                return -1;
            }
            value = new_value;
            capacity = new_capacity;
        }
        value[length] = (char)character;
        length += 1U;
    }
    if (character != EOF && ungetc(character, stream) == EOF) {
        free(value);
        set_line_error(error, error_size, line, "could not read grammar");
        return -1;
    }
    value[length] = '\0';
    if (append_token(tokens, GRAMMAR_TOKEN_IDENTIFIER, value, line) != 0) {
        free(value);
        set_error(error, error_size, "out of memory");
        return -1;
    }
    return 0;
}

static int lex_terminal(FILE *stream, size_t start_line,
                        GrammarTokenList *tokens, char *error,
                        size_t error_size)
{
    StringBuilder builder = {NULL, 0U, 0U};
    int character;
    int escaped;
    size_t line = start_line;

    for (;;) {
        character = fgetc(stream);
        if (character == EOF) {
            free(builder.data);
            set_line_error(error, error_size, line,
                           "unterminated terminal");
            return -1;
        }
        if (character == '\n') {
            free(builder.data);
            set_line_error(error, error_size, line,
                           "newline in terminal");
            return -1;
        }
        if (character == '\'') {
            char *value = string_builder_finish(&builder);

            if (value == NULL ||
                append_token(tokens, GRAMMAR_TOKEN_TERMINAL, value,
                             start_line) != 0) {
                free(value);
                set_error(error, error_size, "out of memory");
                return -1;
            }
            return 0;
        }
        if (character == '\\') {
            escaped = fgetc(stream);
            if (escaped == EOF) {
                free(builder.data);
                set_line_error(error, error_size, line,
                               "unterminated escape");
                return -1;
            }
            if (escaped != '\'' && escaped != '\\') {
                free(builder.data);
                set_line_error(error, error_size, line,
                               "unsupported terminal escape");
                return -1;
            }
            character = escaped;
        }
        if (string_builder_append(&builder, character) != 0) {
            free(builder.data);
            set_error(error, error_size, "out of memory");
            return -1;
        }
    }
}

int grammar_lex_file(const char *path, GrammarTokenList *tokens,
                     char *error, size_t error_size)
{
    FILE *stream;
    int character;
    size_t line = 1U;

    if (path == NULL || tokens == NULL || error == NULL || error_size == 0U) {
        return -1;
    }
    tokens->items = NULL;
    tokens->count = 0U;
    set_error(error, error_size, "could not read grammar");
    stream = fopen(path, "rb");
    if (stream == NULL) {
        set_error(error, error_size, "could not open grammar file");
        return -1;
    }

    for (;;) {
        character = fgetc(stream);
        if (character == EOF) {
            if (ferror(stream) != 0) {
                set_line_error(error, error_size, line,
                               "could not read grammar");
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            break;
        }
        if (is_ascii_space(character)) {
            if (character == '\n') {
                line += 1U;
            }
            continue;
        }
        if (character == '#') {
            do {
                character = fgetc(stream);
            } while (character != EOF && character != '\n');
            if (character == '\n') {
                line += 1U;
            } else if (ferror(stream) != 0) {
                set_line_error(error, error_size, line,
                               "could not read grammar");
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            continue;
        }
        if (character == '%') {
            const char directive[] = "start";
            size_t index;

            for (index = 0U; index < sizeof(directive) - 1U; ++index) {
                int next = fgetc(stream);

                if (next != directive[index]) {
                    if (next != EOF && ungetc(next, stream) == EOF) {
                        set_line_error(error, error_size, line,
                                       "could not read grammar");
                    } else {
                        set_line_error(error, error_size, line,
                                       "invalid directive");
                    }
                    grammar_token_list_destroy(tokens);
                    (void)fclose(stream);
                    return -1;
                }
            }
            if (append_token(tokens, GRAMMAR_TOKEN_START, NULL, line) != 0) {
                set_error(error, error_size, "out of memory");
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            continue;
        }
        if (is_identifier_start(character)) {
            if (lex_identifier(stream, character, line, tokens, error,
                               error_size) != 0) {
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            continue;
        }
        if (character == ':') {
            int second = fgetc(stream);
            int third = second == ':' ? fgetc(stream) : EOF;

            if (second != ':' || third != '=') {
                if (third != EOF) {
                    (void)ungetc(third, stream);
                }
                if (second != EOF) {
                    (void)ungetc(second, stream);
                }
                set_line_error(error, error_size, line,
                               "expected ::= ");
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            if (append_token(tokens, GRAMMAR_TOKEN_DEFINE, NULL, line) != 0) {
                set_error(error, error_size, "out of memory");
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            continue;
        }
        if (character == '|') {
            if (append_token(tokens, GRAMMAR_TOKEN_PIPE, NULL, line) != 0) {
                set_error(error, error_size, "out of memory");
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            continue;
        }
        if (character == ';') {
            if (append_token(tokens, GRAMMAR_TOKEN_SEMICOLON, NULL, line) != 0) {
                set_error(error, error_size, "out of memory");
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            continue;
        }
        if (character == '\'') {
            if (lex_terminal(stream, line, tokens, error, error_size) != 0) {
                grammar_token_list_destroy(tokens);
                (void)fclose(stream);
                return -1;
            }
            continue;
        }
        set_line_error(error, error_size, line, "invalid grammar character");
        grammar_token_list_destroy(tokens);
        (void)fclose(stream);
        return -1;
    }
    if (append_token(tokens, GRAMMAR_TOKEN_EOF, NULL, line) != 0) {
        set_error(error, error_size, "out of memory");
        grammar_token_list_destroy(tokens);
        (void)fclose(stream);
        return -1;
    }
    (void)fclose(stream);
    return 0;
}

void grammar_token_list_destroy(GrammarTokenList *tokens)
{
    size_t index;

    if (tokens == NULL) {
        return;
    }
    for (index = 0U; index < tokens->count; ++index) {
        free(tokens->items[index].value);
    }
    free(tokens->items);
    tokens->items = NULL;
    tokens->count = 0U;
}
