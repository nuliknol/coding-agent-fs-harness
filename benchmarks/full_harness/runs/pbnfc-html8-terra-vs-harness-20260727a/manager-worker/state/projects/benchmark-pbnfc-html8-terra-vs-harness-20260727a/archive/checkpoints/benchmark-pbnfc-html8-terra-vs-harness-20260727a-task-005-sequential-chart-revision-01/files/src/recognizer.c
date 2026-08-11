#include "recognizer.h"

#include "chart.h"

#include <stdint.h>
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

PbnfcRecognitionResult pbnfc_recognize_sequential(
    const PbnfcGrammar *grammar,
    const PbnfcMarkupToken *tokens,
    size_t token_count,
    const char *start_name)
{
    PbnfcChart chart;
    size_t start_production;
    size_t alternative;
    size_t position;
    bool okay = true;
    const char *effective_start;

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
    pbnfc_chart_free(&chart);
    return okay ? PBNFC_RECOGNITION_ACCEPTED : PBNFC_RECOGNITION_REJECTED;
}
