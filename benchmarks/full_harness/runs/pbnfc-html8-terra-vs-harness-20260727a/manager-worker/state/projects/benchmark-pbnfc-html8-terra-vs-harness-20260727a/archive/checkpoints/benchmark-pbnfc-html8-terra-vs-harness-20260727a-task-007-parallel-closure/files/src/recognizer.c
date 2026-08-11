#include "recognizer.h"

#include "chart.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool names_equal(const char *left, const char *right)
{
    return left != NULL && right != NULL && strcmp(left, right) == 0;
}

static bool production_index(const PbnfcGrammar *grammar,
                             const char *name,
                             size_t *index_out)
{
    size_t index;

    for (index = 0U; index < grammar->production_count; ++index) {
        if (names_equal(grammar->productions[index].name, name)) {
            if (index_out != NULL) {
                *index_out = index;
            }
            return true;
        }
    }
    return false;
}

static bool text_matches(const PbnfcGrammarSymbol *symbol,
                         const PbnfcMarkupToken *token)
{
    const char *kind_name;
    size_t name_length;

    if (symbol == NULL || token == NULL || symbol->name == NULL) {
        return false;
    }
    if (symbol->kind == PBNFC_GRAMMAR_SYMBOL_TERMINAL) {
        name_length = strlen(symbol->name);
        return token->length == name_length &&
               (name_length == 0U ||
                memcmp(token->text, symbol->name, name_length) == 0);
    }
    if (symbol->kind != PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE) {
        return false;
    }
    kind_name = pbnfc_markup_token_kind_name(token->kind);
    return names_equal(symbol->name, kind_name);
}

static bool insert_item(PbnfcChart *chart,
                        size_t production,
                        size_t alternative,
                        size_t dot,
                        size_t origin,
                        size_t position)
{
    PbnfcChartItem item = pbnfc_chart_item_make(production,
                                                alternative,
                                                dot,
                                                origin,
                                                position);

    return pbnfc_chart_insert(chart, &item) != PBNFC_CHART_INSERT_ERROR;
}

static bool predict(PbnfcChart *chart,
                    const PbnfcGrammar *grammar,
                    const char *name,
                    size_t position)
{
    size_t production;
    size_t alternative;

    if (!production_index(grammar, name, &production)) {
        return false;
    }
    for (alternative = 0U;
         alternative < grammar->productions[production].alternative_count;
         ++alternative) {
        if (!insert_item(chart, production, alternative, 0U,
                         position, position)) {
            return false;
        }
    }
    return true;
}

static bool complete(PbnfcChart *chart,
                     const PbnfcGrammar *grammar,
                     const PbnfcChartItem *completed,
                     size_t position)
{
    const PbnfcGrammarProduction *completed_production;
    const PbnfcChartSet *origin_set;
    size_t source_index;
    size_t completed_production_index = completed->production;

    completed_production =
        &grammar->productions[completed_production_index];
    origin_set = pbnfc_chart_set_const(chart, completed->origin);
    if (origin_set == NULL) {
        return false;
    }

    /* The origin set can be the current set for an epsilon completion. */
    for (source_index = 0U;
         source_index < pbnfc_chart_set_size(origin_set);
         ++source_index) {
        PbnfcChartItem source_item = *pbnfc_chart_set_at(origin_set,
                                                         source_index);
        const PbnfcGrammarProduction *source_production =
            &grammar->productions[source_item.production];
        const PbnfcGrammarAlternative *source_alternative;
        const PbnfcGrammarSymbol *symbol;

        if (source_item.dot >= source_production->alternatives[
                                    source_item.alternative].symbol_count) {
            continue;
        }
        source_alternative =
            &source_production->alternatives[source_item.alternative];
        symbol = &source_alternative->symbols[source_item.dot];
        if (symbol->kind != PBNFC_GRAMMAR_SYMBOL_NONTERMINAL ||
            !names_equal(symbol->name, completed_production->name)) {
            continue;
        }
        if (!insert_item(chart,
                         source_item.production,
                         source_item.alternative,
                         source_item.dot + 1U,
                         source_item.origin,
                         position)) {
            return false;
        }
    }
    return true;
}

static bool close_position(PbnfcChart *chart,
                           const PbnfcGrammar *grammar,
                           size_t position)
{
    PbnfcChartSet *set = pbnfc_chart_set(chart, position);
    size_t item_index;

    if (set == NULL) {
        return false;
    }
    for (item_index = 0U;
         item_index < pbnfc_chart_set_size(set);
         ++item_index) {
        PbnfcChartItem item = *pbnfc_chart_set_at(set, item_index);
        const PbnfcGrammarProduction *production =
            &grammar->productions[item.production];
        const PbnfcGrammarAlternative *alternative =
            &production->alternatives[item.alternative];

        if (item.dot == alternative->symbol_count) {
            if (!complete(chart, grammar, &item, position)) {
                return false;
            }
        } else {
            const PbnfcGrammarSymbol *symbol =
                &alternative->symbols[item.dot];

            if (symbol->kind == PBNFC_GRAMMAR_SYMBOL_NONTERMINAL &&
                !predict(chart, grammar, symbol->name, position)) {
                return false;
            }
        }
    }
    return true;
}

static bool scan_position(PbnfcChart *chart,
                          const PbnfcGrammar *grammar,
                          const PbnfcMarkupToken *tokens,
                          size_t token_count,
                          size_t position)
{
    const PbnfcChartSet *set;
    const PbnfcMarkupToken *token;
    size_t item_index;

    if (position >= token_count) {
        return true;
    }
    set = pbnfc_chart_set_const(chart, position);
    token = &tokens[position];
    if (set == NULL) {
        return false;
    }
    for (item_index = 0U;
         item_index < pbnfc_chart_set_size(set);
         ++item_index) {
        PbnfcChartItem item = *pbnfc_chart_set_at(set, item_index);
        const PbnfcGrammarProduction *production =
            &grammar->productions[item.production];
        const PbnfcGrammarAlternative *alternative =
            &production->alternatives[item.alternative];
        const PbnfcGrammarSymbol *symbol;

        if (item.dot >= alternative->symbol_count) {
            continue;
        }
        symbol = &alternative->symbols[item.dot];
        if ((symbol->kind == PBNFC_GRAMMAR_SYMBOL_TERMINAL ||
             symbol->kind == PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE) &&
            text_matches(symbol, token) &&
            !insert_item(chart,
                         item.production,
                         item.alternative,
                         item.dot + 1U,
                         item.origin,
                         position + 1U)) {
            return false;
        }
    }
    return true;
}

static bool has_accepting_item(const PbnfcChart *chart,
                               const PbnfcGrammar *grammar,
                               size_t start_production,
                               size_t final_position)
{
    const PbnfcChartSet *set =
        pbnfc_chart_set_const(chart, final_position);
    size_t item_index;

    if (set == NULL) {
        return false;
    }
    for (item_index = 0U;
         item_index < pbnfc_chart_set_size(set);
         ++item_index) {
        const PbnfcChartItem *item = pbnfc_chart_set_at(set, item_index);
        const PbnfcGrammarProduction *production;
        const PbnfcGrammarAlternative *alternative;

        if (item == NULL || item->production != start_production ||
            item->origin != 0U) {
            continue;
        }
        production = &grammar->productions[item->production];
        alternative = &production->alternatives[item->alternative];
        if (item->dot == alternative->symbol_count &&
            item->position == final_position) {
            return true;
        }
    }
    return false;
}

static bool append_expected_text(char **text,
                                 size_t *length,
                                 size_t *capacity,
                                 const char *addition)
{
    size_t addition_length;
    size_t needed;
    size_t next_capacity;
    char *next_text;

    if (text == NULL || length == NULL || capacity == NULL || addition == NULL) {
        return false;
    }
    addition_length = strlen(addition);
    if (*length > SIZE_MAX - addition_length - 1U) {
        return false;
    }
    needed = *length + addition_length + 1U;
    if (needed > *capacity) {
        next_capacity = *capacity == 0U ? 32U : *capacity;
        while (next_capacity < needed) {
            if (next_capacity > SIZE_MAX / 2U) {
                next_capacity = needed;
                break;
            }
            next_capacity *= 2U;
        }
        next_text = (char *)realloc(*text, next_capacity);
        if (next_text == NULL) {
            return false;
        }
        *text = next_text;
        *capacity = next_capacity;
    }
    (void)memcpy(*text + *length, addition, addition_length);
    *length += addition_length;
    (*text)[*length] = '\0';
    return true;
}

static bool expected_symbol_equal(const PbnfcGrammarSymbol *left,
                                  const PbnfcGrammarSymbol *right)
{
    return left != NULL && right != NULL && left->kind == right->kind &&
           names_equal(left->name, right->name);
}

static bool expected_symbol_seen(const PbnfcChartSet *set,
                                 size_t item_index,
                                 const PbnfcGrammar *grammar,
                                 const PbnfcGrammarSymbol *symbol)
{
    size_t prior_index;

    for (prior_index = 0U; prior_index < item_index; ++prior_index) {
        const PbnfcChartItem *prior_item =
            pbnfc_chart_set_at(set, prior_index);
        const PbnfcGrammarProduction *prior_production;
        const PbnfcGrammarAlternative *prior_alternative;
        const PbnfcGrammarSymbol *prior_symbol;

        if (prior_item == NULL) {
            continue;
        }
        prior_production = &grammar->productions[prior_item->production];
        prior_alternative =
            &prior_production->alternatives[prior_item->alternative];
        if (prior_item->dot >= prior_alternative->symbol_count) {
            continue;
        }
        prior_symbol = &prior_alternative->symbols[prior_item->dot];
        if (expected_symbol_equal(prior_symbol, symbol)) {
            return true;
        }
    }
    return false;
}

static bool append_expected_symbol(char **text,
                                   size_t *length,
                                   size_t *capacity,
                                   const PbnfcGrammarSymbol *symbol)
{
    const char *prefix = "";
    const char *suffix = "";

    if (symbol->kind == PBNFC_GRAMMAR_SYMBOL_TERMINAL) {
        prefix = "'";
        suffix = "'";
    } else if (symbol->kind == PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE) {
        prefix = "$";
    }
    return append_expected_text(text, length, capacity, prefix) &&
           append_expected_text(text, length, capacity, symbol->name) &&
           append_expected_text(text, length, capacity, suffix);
}

static char *expected_detail(const PbnfcChartSet *set,
                             const PbnfcGrammar *grammar)
{
    char *text = NULL;
    size_t length = 0U;
    size_t capacity = 0U;
    size_t item_index;

    if (set != NULL) {
        for (item_index = 0U;
             item_index < pbnfc_chart_set_size(set);
             ++item_index) {
            const PbnfcChartItem *item =
                pbnfc_chart_set_at(set, item_index);
            const PbnfcGrammarProduction *production;
            const PbnfcGrammarAlternative *alternative;
            const PbnfcGrammarSymbol *symbol;

            if (item == NULL) {
                continue;
            }
            production = &grammar->productions[item->production];
            alternative = &production->alternatives[item->alternative];
            if (item->dot >= alternative->symbol_count) {
                continue;
            }
            symbol = &alternative->symbols[item->dot];
            if (expected_symbol_seen(set, item_index, grammar, symbol)) {
                continue;
            }
            if (length != 0U &&
                !append_expected_text(&text, &length, &capacity, " | ")) {
                free(text);
                return NULL;
            }
            if (!append_expected_symbol(&text,
                                        &length,
                                        &capacity,
                                        symbol)) {
                free(text);
                return NULL;
            }
        }
    }
    if (length == 0U &&
        !append_expected_text(&text, &length, &capacity, "end of input")) {
        free(text);
        return NULL;
    }
    return text;
}

static PbnfcLocation location_after_token(const PbnfcMarkupToken *token)
{
    PbnfcLocation location;
    size_t index;

    location = token->location;
    if (location.byte_offset > SIZE_MAX - token->length) {
        location.byte_offset = SIZE_MAX;
    } else {
        location.byte_offset += token->length;
    }
    for (index = 0U; index < token->length; ++index) {
        if (token->text[index] == '\n') {
            ++location.line;
            location.column = 1U;
        } else if (location.column != SIZE_MAX) {
            ++location.column;
        }
    }
    return location;
}

static PbnfcLocation eof_location(const PbnfcMarkupToken *tokens,
                                  size_t token_count)
{
    PbnfcLocation location;

    if (token_count == 0U) {
        location.byte_offset = 0U;
        location.line = 1U;
        location.column = 1U;
        return location;
    }
    return location_after_token(&tokens[token_count - 1U]);
}

PbnfcRecognitionResult pbnfc_recognize_sequential(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name)
{
    return pbnfc_recognize_sequential_with_diagnostics(grammar,
                                                       tokens,
                                                       token_count,
                                                       start_name,
                                                       NULL);
}

PbnfcRecognitionResult pbnfc_recognize_sequential_with_diagnostics(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name,
    const PbnfcDiagnosticContext *diagnostics)
{
    PbnfcChart chart;
    size_t start_production;
    size_t alternative;
    size_t position;
    bool okay = true;
    const char *effective_start;
    size_t rejection_position = 0U;
    const PbnfcChartSet *rejection_set = NULL;
    char *expected = NULL;
    PbnfcLocation rejection_location;

    if (grammar == NULL || (tokens == NULL && token_count != 0U) ||
        grammar->start_count == 0U) {
        return PBNFC_RECOGNITION_ERROR;
    }
    effective_start = start_name == NULL ? grammar->start_name : start_name;
    if (effective_start == NULL ||
        !production_index(grammar, effective_start, &start_production) ||
        token_count == SIZE_MAX || !pbnfc_chart_init(&chart, token_count + 1U)) {
        return PBNFC_RECOGNITION_ERROR;
    }

    for (alternative = 0U;
         alternative < grammar->productions[start_production].alternative_count;
         ++alternative) {
        if (!insert_item(&chart, start_production, alternative, 0U, 0U, 0U)) {
            okay = false;
            break;
        }
    }
    for (position = 0U; okay && position <= token_count; ++position) {
        okay = close_position(&chart, grammar, position);
        if (okay && position < token_count) {
            okay = scan_position(&chart,
                                 grammar,
                                 tokens,
                                 token_count,
                                 position);
            if (okay &&
                pbnfc_chart_set_size(pbnfc_chart_set_const(&chart,
                                                          position + 1U)) ==
                    0U) {
                rejection_position = position;
                rejection_set = pbnfc_chart_set_const(&chart, position);
                break;
            }
        }
    }
    if (!okay) {
        pbnfc_chart_free(&chart);
        return PBNFC_RECOGNITION_ERROR;
    }
    okay = has_accepting_item(&chart,
                              grammar,
                              start_production,
                              token_count);
    if (okay) {
        pbnfc_chart_free(&chart);
        return PBNFC_RECOGNITION_ACCEPTED;
    }
    if (rejection_set == NULL) {
        rejection_position = token_count;
        rejection_set = pbnfc_chart_set_const(&chart, token_count);
    }
    expected = expected_detail(rejection_set, grammar);
    if (expected == NULL) {
        pbnfc_chart_free(&chart);
        return PBNFC_RECOGNITION_ERROR;
    }
    rejection_location = rejection_position < token_count
                             ? tokens[rejection_position].location
                             : eof_location(tokens, token_count);
    if (diagnostics != NULL) {
        (void)pbnfc_rejection_emit(diagnostics,
                                   expected,
                                   &rejection_location);
    }
    free(expected);
    pbnfc_chart_free(&chart);
    return PBNFC_RECOGNITION_REJECTED;
}

typedef struct {
    PbnfcChartItem *items;
    size_t count;
    size_t capacity;
} PbnfcCandidateVector;

typedef struct {
    PbnfcChart *chart;
    const PbnfcGrammar *grammar;
    const PbnfcMarkupToken *tokens;
    size_t token_count;
    size_t position;
    size_t begin;
    size_t end;
    bool scanning;
    PbnfcCandidateVector candidates[PBNFC_WORKER_POOL_SIZE];
    size_t tasks[PBNFC_WORKER_POOL_SIZE];
} PbnfcParallelGeneration;

static bool candidate_reserve(PbnfcCandidateVector *vector, size_t needed)
{
    size_t capacity;
    size_t allocation_size;
    PbnfcChartItem *items;

    if (needed <= vector->capacity) {
        return true;
    }
    capacity = vector->capacity == 0U ? 8U : vector->capacity;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2U) {
            capacity = needed;
            break;
        }
        capacity *= 2U;
    }
    if (capacity > SIZE_MAX / sizeof(*items)) {
        return false;
    }
    allocation_size = capacity * sizeof(*items);
    items = (PbnfcChartItem *)realloc(vector->items, allocation_size);
    if (items == NULL) {
        return false;
    }
    vector->items = items;
    vector->capacity = capacity;
    return true;
}

static bool candidate_append(PbnfcCandidateVector *vector,
                             const PbnfcChartItem *item)
{
    if (vector->count == SIZE_MAX ||
        !candidate_reserve(vector, vector->count + 1U)) {
        return false;
    }
    vector->items[vector->count] = *item;
    ++vector->count;
    return true;
}

static void candidate_vectors_free(PbnfcCandidateVector *vectors)
{
    size_t worker_index;

    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        free(vectors[worker_index].items);
        vectors[worker_index].items = NULL;
        vectors[worker_index].count = 0U;
        vectors[worker_index].capacity = 0U;
    }
}

static void candidate_vectors_reset(PbnfcCandidateVector *vectors)
{
    size_t worker_index;

    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        vectors[worker_index].count = 0U;
    }
}

static bool parallel_prediction_candidates(PbnfcParallelGeneration *generation,
                                           size_t worker_index,
                                           const PbnfcChartItem *item,
                                           const PbnfcGrammarSymbol *symbol)
{
    size_t production;
    size_t alternative;
    PbnfcChartItem candidate;

    if (!production_index(generation->grammar, symbol->name, &production)) {
        return false;
    }
    for (alternative = 0U;
         alternative < generation->grammar->productions[production].alternative_count;
         ++alternative) {
        candidate = pbnfc_chart_item_make(production,
                                          alternative,
                                          0U,
                                          generation->position,
                                          generation->position);
        if (!candidate_append(&generation->candidates[worker_index],
                              &candidate)) {
            return false;
        }
    }
    (void)item;
    return true;
}

static bool parallel_completion_candidates(
    PbnfcParallelGeneration *generation,
    size_t worker_index,
    const PbnfcChartItem *completed)
{
    const PbnfcGrammarProduction *completed_production;
    const PbnfcChartSet *origin_set;
    size_t source_index;

    if (completed->production >= generation->grammar->production_count ||
        completed->origin >= pbnfc_chart_set_count(generation->chart)) {
        return false;
    }
    completed_production =
        &generation->grammar->productions[completed->production];
    origin_set = pbnfc_chart_set_const(generation->chart, completed->origin);
    for (source_index = 0U;
         source_index < pbnfc_chart_set_size(origin_set);
         ++source_index) {
        const PbnfcChartItem *source_item =
            pbnfc_chart_set_at(origin_set, source_index);
        const PbnfcGrammarProduction *source_production;
        const PbnfcGrammarAlternative *source_alternative;
        const PbnfcGrammarSymbol *symbol;
        PbnfcChartItem candidate;

        if (source_item == NULL ||
            source_item->production >= generation->grammar->production_count) {
            return false;
        }
        source_production =
            &generation->grammar->productions[source_item->production];
        if (source_item->alternative >= source_production->alternative_count) {
            return false;
        }
        source_alternative =
            &source_production->alternatives[source_item->alternative];
        if (source_item->dot >= source_alternative->symbol_count) {
            continue;
        }
        symbol = &source_alternative->symbols[source_item->dot];
        if (symbol->kind != PBNFC_GRAMMAR_SYMBOL_NONTERMINAL ||
            !names_equal(symbol->name, completed_production->name)) {
            continue;
        }
        candidate = pbnfc_chart_item_make(source_item->production,
                                          source_item->alternative,
                                          source_item->dot + 1U,
                                          source_item->origin,
                                          generation->position);
        if (!candidate_append(&generation->candidates[worker_index],
                              &candidate)) {
            return false;
        }
    }
    return true;
}

static bool parallel_generation_job(size_t worker_index, void *context)
{
    PbnfcParallelGeneration *generation =
        (PbnfcParallelGeneration *)context;
    const PbnfcChartSet *set =
        pbnfc_chart_set_const(generation->chart, generation->position);
    const PbnfcMarkupToken *token = NULL;
    size_t total = generation->end - generation->begin;
    size_t base = total / PBNFC_WORKER_POOL_SIZE;
    size_t remainder = total % PBNFC_WORKER_POOL_SIZE;
    size_t local_begin = generation->begin +
                         worker_index * base +
                         (worker_index < remainder ? worker_index : remainder);
    size_t local_end = local_begin + base +
                       (worker_index < remainder ? 1U : 0U);
    size_t item_index;

    if (set == NULL || local_begin > local_end || local_end > generation->end) {
        return false;
    }
    if (generation->scanning) {
        if (generation->position >= generation->token_count) {
            return false;
        }
        token = &generation->tokens[generation->position];
    }
    for (item_index = local_begin; item_index < local_end; ++item_index) {
        const PbnfcChartItem *item = pbnfc_chart_set_at(set, item_index);
        const PbnfcGrammarProduction *production;
        const PbnfcGrammarAlternative *alternative;
        const PbnfcGrammarSymbol *symbol;

        if (item == NULL || item->production >= generation->grammar->production_count) {
            return false;
        }
        production = &generation->grammar->productions[item->production];
        if (item->alternative >= production->alternative_count) {
            return false;
        }
        alternative = &production->alternatives[item->alternative];
        if (item->dot > alternative->symbol_count) {
            return false;
        }
        ++generation->tasks[worker_index];
        if (generation->scanning) {
            PbnfcChartItem candidate;

            if (item->dot == alternative->symbol_count) {
                continue;
            }
            symbol = &alternative->symbols[item->dot];
            if ((symbol->kind != PBNFC_GRAMMAR_SYMBOL_TERMINAL &&
                 symbol->kind != PBNFC_GRAMMAR_SYMBOL_TOKEN_REFERENCE) ||
                !text_matches(symbol, token)) {
                continue;
            }
            candidate = pbnfc_chart_item_make(item->production,
                                              item->alternative,
                                              item->dot + 1U,
                                              item->origin,
                                              generation->position + 1U);
            if (!candidate_append(&generation->candidates[worker_index],
                                  &candidate)) {
                return false;
            }
        } else if (item->dot == alternative->symbol_count) {
            if (!parallel_completion_candidates(generation,
                                                worker_index,
                                                item)) {
                return false;
            }
        } else {
            symbol = &alternative->symbols[item->dot];
            if (symbol->kind == PBNFC_GRAMMAR_SYMBOL_NONTERMINAL &&
                !parallel_prediction_candidates(generation,
                                                worker_index,
                                                item,
                                                symbol)) {
                return false;
            }
        }
    }
    return true;
}

static int chart_item_compare(const void *left_argument,
                              const void *right_argument)
{
    const PbnfcChartItem *left = (const PbnfcChartItem *)left_argument;
    const PbnfcChartItem *right = (const PbnfcChartItem *)right_argument;

#define PBNFC_COMPARE_FIELD(field) \
    if (left->field < right->field) { \
        return -1; \
    } \
    if (left->field > right->field) { \
        return 1; \
    }
    PBNFC_COMPARE_FIELD(production)
    PBNFC_COMPARE_FIELD(alternative)
    PBNFC_COMPARE_FIELD(dot)
    PBNFC_COMPARE_FIELD(origin)
    PBNFC_COMPARE_FIELD(position)
#undef PBNFC_COMPARE_FIELD
    return 0;
}

static bool merge_parallel_candidates(PbnfcParallelGeneration *generation)
{
    PbnfcChartItem *merged = NULL;
    size_t total = 0U;
    size_t worker_index;
    size_t item_index;
    size_t offset = 0U;

    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        if (total > SIZE_MAX - generation->candidates[worker_index].count) {
            return false;
        }
        total += generation->candidates[worker_index].count;
    }
    if (total != 0U) {
        if (total > SIZE_MAX / sizeof(*merged)) {
            return false;
        }
        merged = (PbnfcChartItem *)malloc(total * sizeof(*merged));
        if (merged == NULL) {
            return false;
        }
    }
    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        for (item_index = 0U;
             item_index < generation->candidates[worker_index].count;
             ++item_index) {
            merged[offset++] =
                generation->candidates[worker_index].items[item_index];
        }
    }
    if (total != 0U) {
        qsort(merged, total, sizeof(*merged), chart_item_compare);
    }
    for (item_index = 0U; item_index < total; ++item_index) {
        if (pbnfc_chart_insert(generation->chart, &merged[item_index]) ==
            PBNFC_CHART_INSERT_ERROR) {
            free(merged);
            return false;
        }
    }
    free(merged);
    return true;
}

static bool run_parallel_generation(PbnfcWorkerPool *pool,
                                    PbnfcParallelGeneration *generation,
                                    PbnfcRecognitionStats *stats)
{
    bool succeeded;
    size_t worker_index;

    candidate_vectors_reset(generation->candidates);
    succeeded = pbnfc_worker_pool_run(pool,
                                      parallel_generation_job,
                                      generation);
    if (!succeeded || !merge_parallel_candidates(generation)) {
        return false;
    }
    if (stats != NULL) {
        ++stats->rounds;
    }
    for (worker_index = 0U;
         worker_index < PBNFC_WORKER_POOL_SIZE;
         ++worker_index) {
        if (stats != NULL) {
            stats->tasks[worker_index] += generation->tasks[worker_index];
        }
        generation->tasks[worker_index] = 0U;
    }
    return true;
}

static bool close_parallel_position(PbnfcWorkerPool *pool,
                                    PbnfcParallelGeneration *generation,
                                    size_t position,
                                    PbnfcRecognitionStats *stats)
{
    size_t cursor = 0U;

    generation->position = position;
    generation->scanning = false;
    while (cursor < pbnfc_chart_set_size(
                        pbnfc_chart_set_const(generation->chart, position))) {
        generation->begin = cursor;
        generation->end = pbnfc_chart_set_size(
            pbnfc_chart_set_const(generation->chart, position));
        if (!run_parallel_generation(pool, generation, stats)) {
            return false;
        }
        cursor = generation->end;
    }
    return true;
}

static bool scan_parallel_position(PbnfcWorkerPool *pool,
                                   PbnfcParallelGeneration *generation,
                                   size_t position,
                                   PbnfcRecognitionStats *stats)
{
    generation->position = position;
    generation->begin = 0U;
    generation->end = pbnfc_chart_set_size(
        pbnfc_chart_set_const(generation->chart, position));
    generation->scanning = true;
    return run_parallel_generation(pool, generation, stats);
}

PbnfcRecognitionResult pbnfc_recognize_parallel(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name,
    PbnfcRecognitionStats *stats)
{
    return pbnfc_recognize_parallel_with_diagnostics(grammar,
                                                     tokens,
                                                     token_count,
                                                     start_name,
                                                     NULL,
                                                     stats);
}

PbnfcRecognitionResult pbnfc_recognize_parallel_with_diagnostics(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name,
    const PbnfcDiagnosticContext *diagnostics,
    PbnfcRecognitionStats *stats)
{
    PbnfcChart chart;
    PbnfcWorkerPool pool = {0};
    PbnfcParallelGeneration generation = {0};
    size_t start_production;
    size_t alternative;
    size_t position;
    size_t rejection_position = 0U;
    const PbnfcChartSet *rejection_set = NULL;
    const char *effective_start;
    char *expected = NULL;
    PbnfcLocation rejection_location;
    PbnfcRecognitionResult result = PBNFC_RECOGNITION_ERROR;

    if (stats != NULL) {
        (void)memset(stats, 0, sizeof(*stats));
    }
    if (grammar == NULL || (tokens == NULL && token_count != 0U) ||
        grammar->start_count == 0U) {
        return PBNFC_RECOGNITION_ERROR;
    }
    effective_start = start_name == NULL ? grammar->start_name : start_name;
    if (effective_start == NULL ||
        !production_index(grammar, effective_start, &start_production) ||
        token_count == SIZE_MAX || !pbnfc_chart_init(&chart, token_count + 1U)) {
        return PBNFC_RECOGNITION_ERROR;
    }
    if (!pbnfc_worker_pool_init(&pool)) {
        pbnfc_chart_free(&chart);
        return PBNFC_RECOGNITION_ERROR;
    }
    if (stats != NULL) {
        stats->workers = pbnfc_worker_pool_worker_count(&pool);
        stats->active_workers = stats->workers;
    }
    generation.chart = &chart;
    generation.grammar = grammar;
    generation.tokens = tokens;
    generation.token_count = token_count;
    for (alternative = 0U;
         alternative < grammar->productions[start_production].alternative_count;
         ++alternative) {
        if (!insert_item(&chart, start_production, alternative, 0U, 0U, 0U)) {
            goto cleanup;
        }
    }
    for (position = 0U; position <= token_count; ++position) {
        if (!close_parallel_position(&pool,
                                     &generation,
                                     position,
                                     stats)) {
            goto cleanup;
        }
        if (position < token_count) {
            if (!scan_parallel_position(&pool,
                                        &generation,
                                        position,
                                        stats)) {
                goto cleanup;
            }
            if (pbnfc_chart_set_size(pbnfc_chart_set_const(&chart,
                                                           position + 1U)) ==
                0U) {
                rejection_position = position;
                rejection_set = pbnfc_chart_set_const(&chart, position);
                break;
            }
        }
    }
    if (has_accepting_item(&chart,
                           grammar,
                           start_production,
                           token_count)) {
        result = PBNFC_RECOGNITION_ACCEPTED;
        goto cleanup;
    }
    if (rejection_set == NULL) {
        rejection_position = token_count;
        rejection_set = pbnfc_chart_set_const(&chart, token_count);
    }
    expected = expected_detail(rejection_set, grammar);
    if (expected == NULL) {
        goto cleanup;
    }
    rejection_location = rejection_position < token_count
                             ? tokens[rejection_position].location
                             : eof_location(tokens, token_count);
    if (diagnostics != NULL) {
        (void)pbnfc_rejection_emit(diagnostics,
                                   expected,
                                   &rejection_location);
    }
    result = PBNFC_RECOGNITION_REJECTED;

cleanup:
    free(expected);
    candidate_vectors_free(generation.candidates);
    pbnfc_worker_pool_free(&pool);
    pbnfc_chart_free(&chart);
    return result;
}
