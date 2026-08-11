#include "grammar_lexer.h"

#include <stddef.h>

static bool is_identifier_start(unsigned char character)
{
    return (character >= (unsigned char)'A' &&
            character <= (unsigned char)'Z') ||
           (character >= (unsigned char)'a' &&
            character <= (unsigned char)'z') ||
           character == (unsigned char)'_';
}

static bool is_identifier_part(unsigned char character)
{
    return is_identifier_start(character) ||
           (character >= (unsigned char)'0' &&
            character <= (unsigned char)'9');
}

static bool is_ignored_space(unsigned char character)
{
    return character == (unsigned char)' ' ||
           character == (unsigned char)'\t' ||
           character == (unsigned char)'\v' ||
           character == (unsigned char)'\f' ||
           character == (unsigned char)'\r' ||
           character == (unsigned char)'\n';
}

static unsigned char current_character(const PbnfcGrammarLexer *lexer)
{
    return (unsigned char)lexer->source[lexer->offset];
}

static void advance_one(PbnfcGrammarLexer *lexer)
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

static void skip_ignored(PbnfcGrammarLexer *lexer)
{
    while (lexer->offset < lexer->length) {
        unsigned char character = current_character(lexer);

        if (is_ignored_space(character)) {
            advance_one(lexer);
        } else if (character == (unsigned char)'#') {
            while (lexer->offset < lexer->length &&
                   current_character(lexer) != (unsigned char)'\n') {
                advance_one(lexer);
            }
        } else {
            break;
        }
    }
}

static bool has_text(const PbnfcGrammarLexer *lexer,
                     size_t offset,
                     const char *text,
                     size_t length)
{
    size_t index;

    if (offset > lexer->length || length > lexer->length - offset) {
        return false;
    }
    for (index = 0U; index < length; ++index) {
        if (lexer->source[offset + index] != text[index]) {
            return false;
        }
    }
    return true;
}

static bool emit_error(PbnfcGrammarLexer *lexer,
                       const PbnfcLocation *location,
                       const char *detail)
{
    lexer->failed = true;
    if (lexer->diagnostics != NULL) {
        (void)pbnfc_diagnostic_emit(lexer->diagnostics, detail, location);
    }
    return false;
}

static void set_token(PbnfcGrammarToken *token,
                      PbnfcGrammarTokenKind kind,
                      PbnfcLocation location,
                      const char *text,
                      size_t length)
{
    token->kind = kind;
    token->location = location;
    token->text = text;
    token->length = length;
}

static bool read_directive(PbnfcGrammarLexer *lexer,
                           PbnfcGrammarToken *token,
                           PbnfcLocation location)
{
    size_t start = lexer->offset;
    size_t length;
    PbnfcGrammarTokenKind kind;

    if (has_text(lexer, start, "%start", 6U)) {
        length = 6U;
        kind = PBNFC_GRAMMAR_TOKEN_START_DIRECTIVE;
    } else if (has_text(lexer, start, "%token", 6U)) {
        length = 6U;
        kind = PBNFC_GRAMMAR_TOKEN_TOKEN_DIRECTIVE;
    } else {
        return emit_error(lexer, &location, "unknown grammar directive");
    }

    if (start + length < lexer->length &&
        is_identifier_part((unsigned char)lexer->source[start + length])) {
        return emit_error(lexer, &location, "malformed grammar directive");
    }

    while (length > 0U) {
        advance_one(lexer);
        --length;
    }
    set_token(token,
              kind,
              location,
              lexer->source + start,
              lexer->offset - start);
    return true;
}

static bool read_identifier(PbnfcGrammarLexer *lexer,
                            PbnfcGrammarToken *token,
                            PbnfcLocation location)
{
    size_t start = lexer->offset;

    while (lexer->offset < lexer->length &&
           is_identifier_part(current_character(lexer))) {
        advance_one(lexer);
    }
    set_token(token,
              PBNFC_GRAMMAR_TOKEN_IDENTIFIER,
              location,
              lexer->source + start,
              lexer->offset - start);
    return true;
}

static bool read_terminal(PbnfcGrammarLexer *lexer,
                          PbnfcGrammarToken *token,
                          PbnfcLocation location)
{
    size_t start = lexer->offset;

    /* Keep the complete source lexeme, including quotes and escape pairs. */
    advance_one(lexer);
    while (lexer->offset < lexer->length) {
        unsigned char character = current_character(lexer);

        if (character == (unsigned char)'\'') {
            advance_one(lexer);
            set_token(token,
                      PBNFC_GRAMMAR_TOKEN_TERMINAL,
                      location,
                      lexer->source + start,
                      lexer->offset - start);
            return true;
        }
        if (character == (unsigned char)'\n' ||
            character == (unsigned char)'\r') {
            return emit_error(lexer, &location, "unterminated grammar terminal");
        }
        if (character == (unsigned char)'\\') {
            advance_one(lexer);
            if (lexer->offset == lexer->length ||
                (current_character(lexer) != (unsigned char)'\'' &&
                 current_character(lexer) != (unsigned char)'\\')) {
                return emit_error(lexer, &location, "invalid grammar terminal escape");
            }
        }
        advance_one(lexer);
    }

    return emit_error(lexer, &location, "unterminated grammar terminal");
}

static bool read_reference(PbnfcGrammarLexer *lexer,
                           PbnfcGrammarToken *token,
                           PbnfcLocation location)
{
    size_t start = lexer->offset;

    advance_one(lexer);
    if (lexer->offset == lexer->length ||
        !is_identifier_start(current_character(lexer))) {
        return emit_error(lexer, &location, "malformed grammar token reference");
    }
    while (lexer->offset < lexer->length &&
           is_identifier_part(current_character(lexer))) {
        advance_one(lexer);
    }
    set_token(token,
              PBNFC_GRAMMAR_TOKEN_REFERENCE,
              location,
              lexer->source + start,
              lexer->offset - start);
    return true;
}

void pbnfc_grammar_lexer_init(PbnfcGrammarLexer *lexer,
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
    lexer->diagnostics = diagnostics;
    lexer->failed = source == NULL && length != 0U;
}

bool pbnfc_grammar_lexer_next(PbnfcGrammarLexer *lexer,
                               PbnfcGrammarToken *token)
{
    PbnfcLocation location;
    size_t start;

    if (lexer == NULL || token == NULL || lexer->failed) {
        return false;
    }
    if (lexer->source == NULL && lexer->length != 0U) {
        return emit_error(lexer, NULL, "grammar source is unavailable");
    }

    skip_ignored(lexer);
    location.byte_offset = lexer->offset;
    location.line = lexer->line;
    location.column = lexer->column;
    start = lexer->offset;

    if (lexer->offset == lexer->length) {
        set_token(token,
                  PBNFC_GRAMMAR_TOKEN_EOF,
                  location,
                  lexer->source == NULL ? NULL : lexer->source + start,
                  0U);
        return true;
    }

    switch (current_character(lexer)) {
    case (unsigned char)'%':
        return read_directive(lexer, token, location);
    case (unsigned char)':':
        if (!has_text(lexer, start, "::=", 3U)) {
            return emit_error(lexer, &location, "expected ::= punctuation");
        }
        advance_one(lexer);
        advance_one(lexer);
        advance_one(lexer);
        set_token(token,
                  PBNFC_GRAMMAR_TOKEN_ASSIGN,
                  location,
                  lexer->source + start,
                  3U);
        return true;
    case (unsigned char)'|':
        advance_one(lexer);
        set_token(token,
                  PBNFC_GRAMMAR_TOKEN_PIPE,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    case (unsigned char)';':
        advance_one(lexer);
        set_token(token,
                  PBNFC_GRAMMAR_TOKEN_SEMICOLON,
                  location,
                  lexer->source + start,
                  1U);
        return true;
    case (unsigned char)'\'':
        return read_terminal(lexer, token, location);
    case (unsigned char)'$':
        return read_reference(lexer, token, location);
    default:
        if (is_identifier_start(current_character(lexer))) {
            return read_identifier(lexer, token, location);
        }
        return emit_error(lexer, &location, "invalid character in grammar");
    }
}

bool pbnfc_grammar_lexer_failed(const PbnfcGrammarLexer *lexer)
{
    return lexer == NULL || lexer->failed;
}

const char *pbnfc_grammar_token_kind_name(PbnfcGrammarTokenKind kind)
{
    switch (kind) {
    case PBNFC_GRAMMAR_TOKEN_EOF:
        return "eof";
    case PBNFC_GRAMMAR_TOKEN_START_DIRECTIVE:
        return "%start";
    case PBNFC_GRAMMAR_TOKEN_TOKEN_DIRECTIVE:
        return "%token";
    case PBNFC_GRAMMAR_TOKEN_IDENTIFIER:
        return "identifier";
    case PBNFC_GRAMMAR_TOKEN_TERMINAL:
        return "terminal";
    case PBNFC_GRAMMAR_TOKEN_REFERENCE:
        return "token-reference";
    case PBNFC_GRAMMAR_TOKEN_ASSIGN:
        return "::=";
    case PBNFC_GRAMMAR_TOKEN_PIPE:
        return "|";
    case PBNFC_GRAMMAR_TOKEN_SEMICOLON:
        return ";";
    }
    return "unknown";
}
