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

static bool text_has_nonspace(const PbnfcMarkupLexer *lexer, size_t start)
{
    size_t offset = start;

    while (offset < lexer->offset) {
        if (!is_layout_space((unsigned char)lexer->source[offset])) {
            return true;
        }
        ++offset;
    }
    return false;
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

static bool emit_error(PbnfcMarkupLexer *lexer,
                       const PbnfcLocation *location,
                       const char *detail)
{
    lexer->failed = true;
    if (lexer->diagnostics != NULL) {
        (void)pbnfc_diagnostic_emit(lexer->diagnostics, detail, location);
    }
    return false;
}

static bool fail_at_current(PbnfcMarkupLexer *lexer, const char *detail)
{
    PbnfcLocation location;

    location.byte_offset = lexer->offset;
    location.line = lexer->line;
    location.column = lexer->column;
    return emit_error(lexer, &location, detail);
}

static bool tag_state_allows_end(PbnfcMarkupTagState state)
{
    return state == PBNFC_MARKUP_TAG_AFTER_NAME ||
           state == PBNFC_MARKUP_TAG_AFTER_VALUE ||
           state == PBNFC_MARKUP_TAG_AFTER_CLOSE_NAME ||
           state == PBNFC_MARKUP_TAG_EXPECT_SELF_CLOSE_END;
}

static bool tag_state_allows_slash(PbnfcMarkupTagState state)
{
    return state == PBNFC_MARKUP_TAG_EXPECT_NAME ||
           state == PBNFC_MARKUP_TAG_AFTER_NAME ||
           state == PBNFC_MARKUP_TAG_AFTER_VALUE;
}

static bool tag_state_allows_identifier(PbnfcMarkupTagState state)
{
    return state == PBNFC_MARKUP_TAG_EXPECT_NAME ||
           state == PBNFC_MARKUP_TAG_EXPECT_CLOSE_NAME ||
           state == PBNFC_MARKUP_TAG_AFTER_NAME ||
           state == PBNFC_MARKUP_TAG_EXPECT_VALUE ||
           state == PBNFC_MARKUP_TAG_AFTER_VALUE;
}

static bool read_string(PbnfcMarkupLexer *lexer,
                        PbnfcMarkupToken *token,
                        PbnfcLocation location)
{
    const size_t start = lexer->offset;
    const unsigned char quote = current_character(lexer);

    advance_one(lexer);
    while (lexer->offset < lexer->length) {
        unsigned char character = current_character(lexer);

        if (character >= 0x80U) {
            return fail_at_current(lexer, "invalid markup byte");
        }
        if (character == (unsigned char)'\\') {
            advance_one(lexer);
            if (lexer->offset == lexer->length) {
                return emit_error(lexer,
                                  &location,
                                  "unterminated markup quoted value");
            }
            character = current_character(lexer);
            if (character != quote && character != (unsigned char)'\\') {
                return emit_error(lexer,
                                  &location,
                                  "invalid markup value escape");
            }
            advance_one(lexer);
            continue;
        }
        if (character == quote) {
            advance_one(lexer);
            lexer->tag_state = PBNFC_MARKUP_TAG_AFTER_VALUE;
            set_token(token,
                      PBNFC_MARKUP_TOKEN_STRING,
                      location,
                      lexer->source + start,
                      lexer->offset - start);
            return true;
        }
        advance_one(lexer);
    }

    return emit_error(lexer,
                      &location,
                      "unterminated markup quoted value");
}

void pbnfc_markup_lexer_init(PbnfcMarkupLexer *lexer,
                             const char *source,
                             size_t length,
                             const PbnfcDiagnosticContext *diagnostics)
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
    lexer->tag_state = PBNFC_MARKUP_TAG_EXPECT_NAME;
    lexer->diagnostics = diagnostics;
    lexer->failed = false;
}

bool pbnfc_markup_lexer_next(PbnfcMarkupLexer *lexer,
                             PbnfcMarkupToken *token)
{
    PbnfcLocation location;
    size_t start;
    unsigned char character;

    if (lexer == NULL || token == NULL || lexer->failed) {
        return false;
    }
    if (lexer->source == NULL && lexer->length != 0U) {
        return fail_at_current(lexer, "markup source is unavailable");
    }

    if (lexer->in_tag) {
        skip_layout_space(lexer);
    } else {
        for (;;) {
            start = lexer->offset;
            location.byte_offset = start;
            location.line = lexer->line;
            location.column = lexer->column;

            while (lexer->offset < lexer->length &&
                   current_character(lexer) != (unsigned char)'<') {
                advance_one(lexer);
            }
            if (lexer->offset != start) {
                if (text_has_nonspace(lexer, start)) {
                    set_token(token,
                              PBNFC_MARKUP_TOKEN_TEXT,
                              location,
                              lexer->source + start,
                              lexer->offset - start);
                    return true;
                }
                continue;
            }
            break;
        }
    }

    if (lexer->offset == lexer->length) {
        if (lexer->in_tag) {
            return fail_at_current(lexer, "unterminated markup tag");
        }
        location.byte_offset = lexer->offset;
        location.line = lexer->line;
        location.column = lexer->column;
        set_token(token,
                  PBNFC_MARKUP_TOKEN_EOF,
                  location,
                  lexer->source == NULL ? NULL : lexer->source + lexer->offset,
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
            return fail_at_current(lexer, "invalid markup byte");
        }
        advance_one(lexer);
        lexer->in_tag = true;
        lexer->tag_state = PBNFC_MARKUP_TAG_EXPECT_NAME;
        set_token(token,
                  PBNFC_MARKUP_TOKEN_LESS_THAN,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    }

    if (character >= 0x80U) {
        return fail_at_current(lexer, "invalid markup byte");
    }
    if (character == (unsigned char)'<') {
        return fail_at_current(lexer, "invalid markup tag transition");
    }
    if (character == (unsigned char)'>') {
        if (!tag_state_allows_end(lexer->tag_state)) {
            return fail_at_current(lexer, "invalid markup tag transition");
        }
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
        if (!tag_state_allows_slash(lexer->tag_state)) {
            return fail_at_current(lexer, "invalid markup tag transition");
        }
        advance_one(lexer);
        if (lexer->tag_state == PBNFC_MARKUP_TAG_EXPECT_NAME) {
            lexer->tag_state = PBNFC_MARKUP_TAG_EXPECT_CLOSE_NAME;
        } else {
            lexer->tag_state = PBNFC_MARKUP_TAG_EXPECT_SELF_CLOSE_END;
        }
        set_token(token,
                  PBNFC_MARKUP_TOKEN_SLASH,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    }
    if (character == (unsigned char)'=') {
        if (lexer->tag_state != PBNFC_MARKUP_TAG_EXPECT_EQUALS) {
            return fail_at_current(lexer, "invalid markup tag transition");
        }
        advance_one(lexer);
        lexer->tag_state = PBNFC_MARKUP_TAG_EXPECT_VALUE;
        set_token(token,
                  PBNFC_MARKUP_TOKEN_EQUALS,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    }
    if (character == (unsigned char)'\'' ||
        character == (unsigned char)'"') {
        if (lexer->tag_state != PBNFC_MARKUP_TAG_EXPECT_VALUE) {
            return fail_at_current(lexer, "invalid markup tag transition");
        }
        return read_string(lexer, token, location);
    }
    if (is_identifier_start(character)) {
        if (!tag_state_allows_identifier(lexer->tag_state)) {
            return fail_at_current(lexer, "invalid markup tag transition");
        }
        do {
            advance_one(lexer);
        } while (lexer->offset < lexer->length &&
                 is_identifier_part(current_character(lexer)));
        if (lexer->tag_state == PBNFC_MARKUP_TAG_EXPECT_NAME) {
            lexer->tag_state = PBNFC_MARKUP_TAG_AFTER_NAME;
        } else if (lexer->tag_state == PBNFC_MARKUP_TAG_EXPECT_CLOSE_NAME) {
            lexer->tag_state = PBNFC_MARKUP_TAG_AFTER_CLOSE_NAME;
        } else if (lexer->tag_state == PBNFC_MARKUP_TAG_EXPECT_VALUE) {
            lexer->tag_state = PBNFC_MARKUP_TAG_AFTER_VALUE;
        } else {
            lexer->tag_state = PBNFC_MARKUP_TAG_EXPECT_EQUALS;
        }
        set_token(token,
                  PBNFC_MARKUP_TOKEN_IDENT,
                  location,
                  lexer->source + start,
                  lexer->offset - start);
        return true;
    }

    return fail_at_current(lexer, "invalid markup punctuation");
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
    case PBNFC_MARKUP_TOKEN_STRING:
        return "STRING";
    case PBNFC_MARKUP_TOKEN_TEXT:
        return "TEXT";
    }
    return "unknown";
}
