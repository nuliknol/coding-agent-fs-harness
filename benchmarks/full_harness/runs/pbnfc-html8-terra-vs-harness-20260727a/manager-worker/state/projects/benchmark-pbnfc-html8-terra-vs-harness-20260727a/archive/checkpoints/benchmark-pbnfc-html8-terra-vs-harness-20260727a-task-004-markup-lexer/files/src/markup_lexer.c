#include "markup_lexer.h"

static bool is_layout_space(unsigned char character)
{
    return character == (unsigned char)' ' ||
           character == (unsigned char)'\t' ||
           character == (unsigned char)'\v' ||
           character == (unsigned char)'\f' ||
           character == (unsigned char)'\r' ||
           character == (unsigned char)'\n';
}

static bool is_identifier_start(unsigned char character)
{
    return (character >= (unsigned char)'A' &&
            character <= (unsigned char)'Z') ||
           (character >= (unsigned char)'a' &&
            character <= (unsigned char)'z') ||
           character == (unsigned char)'_' ||
           character == (unsigned char)':';
}

static bool is_identifier_part(unsigned char character)
{
    return is_identifier_start(character) ||
           (character >= (unsigned char)'0' &&
            character <= (unsigned char)'9') ||
           character == (unsigned char)'.' ||
           character == (unsigned char)'-';
}

static unsigned char current_character(const PbnfcMarkupLexer *lexer)
{
    return (unsigned char)lexer->source[lexer->offset];
}

static void advance_one(PbnfcMarkupLexer *lexer)
{
    unsigned char character = current_character(lexer);

    ++lexer->offset;
    if (character == (unsigned char)'\n') {
        ++lexer->line;
        lexer->column = 1U;
    } else {
        ++lexer->column;
    }
}

static void skip_layout_space(PbnfcMarkupLexer *lexer)
{
    while (lexer->offset < lexer->length &&
           is_layout_space(current_character(lexer))) {
        advance_one(lexer);
    }
}

static void set_token(PbnfcMarkupToken *token,
                      PbnfcMarkupTokenKind kind,
                      PbnfcLocation location,
                      const char *text,
                      size_t length)
{
    token->kind = kind;
    token->location = location;
    token->text = text;
    token->length = length;
}

static bool fail_lexer(PbnfcMarkupLexer *lexer)
{
    lexer->failed = true;
    return false;
}

void pbnfc_markup_lexer_init(PbnfcMarkupLexer *lexer,
                             const char *source,
                             size_t length)
{
    if (lexer == NULL) {
        return;
    }
    lexer->source = source;
    lexer->length = length;
    lexer->offset = 0U;
    lexer->line = 1U;
    lexer->column = 1U;
    lexer->in_tag = false;
    lexer->failed = source == NULL && length != 0U;
}

bool pbnfc_markup_lexer_next(PbnfcMarkupLexer *lexer,
                             PbnfcMarkupToken *token)
{
    PbnfcLocation location;
    size_t start;
    unsigned char character;

    if (lexer == NULL || token == NULL || lexer->failed ||
        lexer->source == NULL) {
        return false;
    }

    skip_layout_space(lexer);
    if (lexer->offset == lexer->length) {
        if (lexer->in_tag) {
            return fail_lexer(lexer);
        }
        location.byte_offset = lexer->offset;
        location.line = lexer->line;
        location.column = lexer->column;
        set_token(token,
                  PBNFC_MARKUP_TOKEN_EOF,
                  location,
                  lexer->source + lexer->offset,
                  0U);
        return true;
    }

    start = lexer->offset;
    location.byte_offset = start;
    location.line = lexer->line;
    location.column = lexer->column;
    character = current_character(lexer);

    if (!lexer->in_tag) {
        if (character != (unsigned char)'<') {
            return fail_lexer(lexer);
        }
        advance_one(lexer);
        lexer->in_tag = true;
        set_token(token,
                  PBNFC_MARKUP_TOKEN_LESS_THAN,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    }

    if (character == (unsigned char)'<') {
        return fail_lexer(lexer);
    }
    if (character == (unsigned char)'>') {
        advance_one(lexer);
        lexer->in_tag = false;
        set_token(token,
                  PBNFC_MARKUP_TOKEN_GREATER_THAN,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    }
    if (character == (unsigned char)'/') {
        advance_one(lexer);
        set_token(token,
                  PBNFC_MARKUP_TOKEN_SLASH,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    }
    if (character == (unsigned char)'=') {
        advance_one(lexer);
        set_token(token,
                  PBNFC_MARKUP_TOKEN_EQUALS,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    }
    if (is_identifier_start(character)) {
        do {
            advance_one(lexer);
        } while (lexer->offset < lexer->length &&
                 is_identifier_part(current_character(lexer)));
        set_token(token,
                  PBNFC_MARKUP_TOKEN_IDENT,
                  location,
                  lexer->source + start,
                  lexer->offset - start);
        return true;
    }

    return fail_lexer(lexer);
}

bool pbnfc_markup_lexer_failed(const PbnfcMarkupLexer *lexer)
{
    return lexer != NULL && lexer->failed;
}

const char *pbnfc_markup_token_kind_name(PbnfcMarkupTokenKind kind)
{
    switch (kind) {
    case PBNFC_MARKUP_TOKEN_EOF:
        return "EOF";
    case PBNFC_MARKUP_TOKEN_LESS_THAN:
        return "<";
    case PBNFC_MARKUP_TOKEN_GREATER_THAN:
        return ">";
    case PBNFC_MARKUP_TOKEN_SLASH:
        return "/";
    case PBNFC_MARKUP_TOKEN_EQUALS:
        return "=";
    case PBNFC_MARKUP_TOKEN_IDENT:
        return "IDENT";
    }
    return "unknown";
}
