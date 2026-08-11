#include "recognizer.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t rule;
    size_t alternative;
    size_t dot;
    size_t origin;
} ChartItem;

typedef struct {
    ChartItem *data;
    size_t count;
    size_t capacity;
} ItemVector;

typedef struct {
    ChartItem *data;
    size_t count;
    size_t capacity;
} CandidateVector;

typedef struct {
    const Grammar *grammar;
    ItemVector *charts;
    size_t position;
    CandidateVector *candidates;
    size_t *task_counts;
    atomic_int failed;
} ClosureWork;

typedef struct {
    const Grammar *grammar;
    const Markup *markup;
    const ItemVector *current;
    size_t position;
    CandidateVector *candidates;
    size_t *task_counts;
    atomic_int failed;
} ScanWork;

static int item_equal(const ChartItem *a, const ChartItem *b)
{
    return a->rule == b->rule && a->alternative == b->alternative &&
           a->dot == b->dot && a->origin == b->origin;
}

static int vector_grow(ChartItem **data, size_t *capacity, size_t needed)
{
    size_t next = *capacity == 0 ? 16 : *capacity * 2;
    ChartItem *grown;
    if (*capacity >= needed)
        return 0;
    while (next < needed) {
        if (next > ((size_t)-1) / 2)
            return -1;
        next *= 2;
    }
    grown = (ChartItem *)realloc(*data, next * sizeof(*grown));
    if (grown == NULL)
        return -1;
    *data = grown;
    *capacity = next;
    return 0;
}

static int add_item(ItemVector *vector, ChartItem item)
{
    size_t i;
    for (i = 0; i < vector->count; i++)
        if (item_equal(&vector->data[i], &item))
            return 0;
    if (vector_grow(&vector->data, &vector->capacity, vector->count + 1) != 0)
        return -1;
    vector->data[vector->count++] = item;
    return 1;
}

static int add_candidate(CandidateVector *vector, ChartItem item, atomic_int *failed)
{
    if (vector_grow(&vector->data, &vector->capacity, vector->count + 1) != 0) {
        atomic_store(failed, 1);
        return -1;
    }
    vector->data[vector->count++] = item;
    return 0;
}

static size_t rule_index(const Grammar *grammar, const char *name)
{
    size_t i;
    for (i = 0; i < grammar->rule_count; i++)
        if (strcmp(grammar->rules[i].name, name) == 0)
            return i;
    return (size_t)-1;
}

static const GrammarSymbol *next_symbol(const Grammar *grammar, const ChartItem *item)
{
    const Alternative *alternative = &grammar->rules[item->rule].alternatives[item->alternative];
    if (item->dot >= alternative->count)
        return NULL;
    return &alternative->symbols[item->dot];
}

static void closure_task(void *context, size_t worker, size_t begin, size_t end)
{
    ClosureWork *work = (ClosureWork *)context;
    ItemVector *current = &work->charts[work->position];
    CandidateVector *out = &work->candidates[worker];
    size_t i;
    if (begin < end)
        work->task_counts[worker]++;
    for (i = begin; i < end && !atomic_load(&work->failed); i++) {
        ChartItem item = current->data[i];
        const GrammarSymbol *symbol = next_symbol(work->grammar, &item);
        if (symbol != NULL && symbol->kind == SYM_NONTERM) {
            size_t target = rule_index(work->grammar, symbol->text);
            size_t j;
            for (j = 0; j < work->grammar->rules[target].count; j++) {
                ChartItem candidate = {target, j, 0, work->position};
                if (add_candidate(out, candidate, &work->failed) != 0)
                    return;
            }
            /* Prediction can follow an epsilon constituent already in this chart. */
            for (j = 0; j < current->count; j++) {
                ChartItem completed = current->data[j];
                if (completed.rule == target && completed.origin == work->position &&
                    next_symbol(work->grammar, &completed) == NULL) {
                    ChartItem candidate = {item.rule, item.alternative, item.dot + 1, item.origin};
                    if (add_candidate(out, candidate, &work->failed) != 0)
                        return;
                }
            }
        } else if (symbol == NULL) {
            size_t j;
            if (item.origin > work->position)
                continue;
            for (j = 0; j < work->charts[item.origin].count; j++) {
                ChartItem parent = work->charts[item.origin].data[j];
                const GrammarSymbol *wanted = next_symbol(work->grammar, &parent);
                if (wanted != NULL && wanted->kind == SYM_NONTERM &&
                    rule_index(work->grammar, wanted->text) == item.rule) {
                    ChartItem candidate = {parent.rule, parent.alternative, parent.dot + 1, parent.origin};
                    if (add_candidate(out, candidate, &work->failed) != 0)
                        return;
                }
            }
        }
    }
}

static int token_matches(const GrammarSymbol *symbol, const MarkupToken *token)
{
    if (symbol->kind == SYM_LITERAL)
        return strcmp(symbol->text, token->lexeme) == 0;
    if (symbol->kind == SYM_TOKEN) {
        if (symbol->token_kind == TOK_IDENT) return token->kind == MARKUP_IDENT;
        if (symbol->token_kind == TOK_STRING) return token->kind == MARKUP_STRING;
        return token->kind == MARKUP_TEXT;
    }
    return 0;
}

static void scan_task(void *context, size_t worker, size_t begin, size_t end)
{
    ScanWork *work = (ScanWork *)context;
    CandidateVector *out = &work->candidates[worker];
    size_t i;
    if (end > work->current->count)
        end = work->current->count;
    if (begin < end)
        work->task_counts[worker]++;
    for (i = begin; i < end && !atomic_load(&work->failed); i++) {
        const ChartItem *item = &work->current->data[i];
        const GrammarSymbol *symbol = next_symbol(work->grammar, item);
        if (symbol != NULL && symbol->kind != SYM_NONTERM &&
            token_matches(symbol, &work->markup->tokens[work->position])) {
            ChartItem candidate = {item->rule, item->alternative, item->dot + 1, item->origin};
            if (add_candidate(out, candidate, &work->failed) != 0)
                return;
        }
    }
}

static int candidate_compare(const void *left, const void *right)
{
    const ChartItem *a = (const ChartItem *)left;
    const ChartItem *b = (const ChartItem *)right;
    if (a->rule != b->rule) return a->rule < b->rule ? -1 : 1;
    if (a->alternative != b->alternative) return a->alternative < b->alternative ? -1 : 1;
    if (a->dot != b->dot) return a->dot < b->dot ? -1 : 1;
    if (a->origin != b->origin) return a->origin < b->origin ? -1 : 1;
    return 0;
}

static int merge_candidates(ItemVector *target, CandidateVector *vectors)
{
    size_t total = 0;
    size_t i;
    ChartItem *all;
    size_t at = 0;
    for (i = 0; i < 8; i++)
        total += vectors[i].count;
    if (total == 0)
        return 0;
    all = (ChartItem *)malloc(total * sizeof(*all));
    if (all == NULL)
        return -1;
    for (i = 0; i < 8; i++) {
        memcpy(all + at, vectors[i].data, vectors[i].count * sizeof(*all));
        at += vectors[i].count;
    }
    qsort(all, total, sizeof(*all), candidate_compare);
    for (i = 0; i < total; i++) {
        if (add_item(target, all[i]) < 0) {
            free(all);
            return -1;
        }
    }
    free(all);
    return 0;
}

static void clear_candidates(CandidateVector *vectors)
{
    size_t i;
    for (i = 0; i < 8; i++)
        vectors[i].count = 0;
}

static void free_candidates(CandidateVector *vectors)
{
    size_t i;
    for (i = 0; i < 8; i++)
        free(vectors[i].data);
}

static void free_charts(ItemVector *charts, size_t count)
{
    size_t i;
    for (i = 0; i < count; i++)
        free(charts[i].data);
    free(charts);
}

static void expected_append(char *expected, size_t capacity, const char *text)
{
    size_t used = strlen(expected);
    while (*text != '\0' && used + 1 < capacity)
        expected[used++] = *text++;
    expected[used] = '\0';
}

static void expected_append_literal(char *expected, size_t capacity, const char *text)
{
    char escaped[8];
    unsigned char c;
    expected_append(expected, capacity, "'");
    while (*text != '\0') {
        c = (unsigned char)*text++;
        if (c == '\n') expected_append(expected, capacity, "\\n");
        else if (c == '\r') expected_append(expected, capacity, "\\r");
        else if (c == '\t') expected_append(expected, capacity, "\\t");
        else if (c == '\\') expected_append(expected, capacity, "\\\\");
        else if (c == '\'') expected_append(expected, capacity, "\\'");
        else if (c < 0x20 || c >= 0x7f) {
            (void)snprintf(escaped, sizeof(escaped), "\\x%02X", (unsigned)c);
            expected_append(expected, capacity, escaped);
        } else {
            size_t used = strlen(expected);
            if (used + 1 < capacity) {
                expected[used] = (char)c;
                expected[used + 1] = '\0';
            }
        }
    }
    expected_append(expected, capacity, "'");
}

static void expected_add(char *expected, size_t capacity, const GrammarSymbol *symbol)
{
    if (expected[0] != '\0')
        expected_append(expected, capacity, ", ");
    if (symbol->kind == SYM_LITERAL)
        expected_append_literal(expected, capacity, symbol->text);
    else if (symbol->token_kind == TOK_IDENT)
        expected_append(expected, capacity, "$IDENT");
    else if (symbol->token_kind == TOK_STRING)
        expected_append(expected, capacity, "$STRING");
    else
        expected_append(expected, capacity, "$TEXT");
}

int recognize(const Grammar *grammar, const Markup *markup, Recognition *result)
{
    WorkerPool pool;
    ItemVector *charts;
    CandidateVector candidates[8];
    size_t chart_count = markup->count + 1;
    size_t position;
    int pool_ok = 0;
    memset(result, 0, sizeof(*result));
    memset(&pool, 0, sizeof(pool));
    memset(candidates, 0, sizeof(candidates));
    charts = (ItemVector *)calloc(chart_count, sizeof(*charts));
    if (charts == NULL)
        return -1;
    if (pool_start(&pool) != 0) {
        free_charts(charts, chart_count);
        return -1;
    }
    pool_ok = 1;
    for (position = 0; position < grammar->rules[grammar->start_rule].count; position++) {
        ChartItem seed = {grammar->start_rule, position, 0, 0};
        if (add_item(&charts[0], seed) < 0)
            goto failed;
    }
    for (position = 0; position <= markup->count; position++) {
        size_t processed = 0;
        while (processed < charts[position].count) {
            ClosureWork work;
            size_t snapshot = charts[position].count;
            clear_candidates(candidates);
            work.grammar = grammar;
            work.charts = charts;
            work.position = position;
            work.candidates = candidates;
            work.task_counts = result->tasks;
            atomic_init(&work.failed, 0);
            if (pool_run_range(&pool, processed, snapshot, closure_task, &work) != 0 ||
                atomic_load(&work.failed))
                goto failed;
            result->rounds++;
            if (merge_candidates(&charts[position], candidates) != 0)
                goto failed;
            processed = snapshot;
        }
        if (position < markup->count) {
            ScanWork work;
            clear_candidates(candidates);
            work.grammar = grammar;
            work.markup = markup;
            work.current = &charts[position];
            work.position = position;
            work.candidates = candidates;
            work.task_counts = result->tasks;
            atomic_init(&work.failed, 0);
            if (pool_run_range(&pool, 0, charts[position].count, scan_task, &work) != 0 ||
                atomic_load(&work.failed))
                goto failed;
            result->rounds++;
            if (merge_candidates(&charts[position + 1], candidates) != 0)
                goto failed;
        }
    }
    result->accepted = 0;
    {
        size_t i;
        for (i = 0; i < charts[markup->count].count; i++) {
            ChartItem item = charts[markup->count].data[i];
            if (item.rule == grammar->start_rule && item.origin == 0 &&
                next_symbol(grammar, &item) == NULL) {
                result->accepted = 1;
                break;
            }
        }
    }
    if (!result->accepted) {
        size_t furthest = 0;
        for (position = 0; position <= markup->count; position++) {
            size_t i;
            int active = 0;
            for (i = 0; i < charts[position].count; i++)
                if (next_symbol(grammar, &charts[position].data[i]) != NULL)
                    active = 1;
            if (active)
                furthest = position;
        }
        result->error_position = furthest;
        result->expected[0] = '\0';
        for (position = 0; position < charts[furthest].count; position++) {
            const GrammarSymbol *symbol = next_symbol(grammar, &charts[furthest].data[position]);
            if (symbol != NULL && symbol->kind != SYM_NONTERM)
                expected_add(result->expected, sizeof(result->expected), symbol);
        }
        if (result->expected[0] == '\0')
            (void)snprintf(result->expected, sizeof(result->expected), "markup token");
    }
    free_candidates(candidates);
    if (pool_ok)
        pool_stop(&pool);
    free_charts(charts, chart_count);
    return 0;

failed:
    free_candidates(candidates);
    if (pool_ok)
        pool_stop(&pool);
    free_charts(charts, chart_count);
    return -1;
}
