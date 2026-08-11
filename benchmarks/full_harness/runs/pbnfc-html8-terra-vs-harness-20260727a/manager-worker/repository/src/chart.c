#include "chart.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static bool size_mul_ok(size_t left, size_t right, size_t *result)
{
    if (left != 0U && right > SIZE_MAX / left) {
        return false;
    }
    *result = left * right;
    return true;
}

static bool chart_set_reserve(PbnfcChartSet *set, size_t needed)
{
    PbnfcChartItem *items;
    size_t capacity;
    size_t allocation_size;

    if (needed <= set->capacity) {
        return true;
    }
    capacity = set->capacity == 0U ? 8U : set->capacity;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2U) {
            capacity = needed;
            break;
        }
        capacity *= 2U;
    }
    if (!size_mul_ok(capacity, sizeof(*items), &allocation_size)) {
        return false;
    }
    items = realloc(set->items, allocation_size);
    if (items == NULL) {
        return false;
    }
    set->items = items;
    set->capacity = capacity;
    return true;
}

PbnfcChartItem pbnfc_chart_item_make(size_t production,
                                     size_t alternative,
                                     size_t dot,
                                     size_t origin,
                                     size_t position)
{
    PbnfcChartItem item;

    item.production = production;
    item.alternative = alternative;
    item.dot = dot;
    item.origin = origin;
    item.position = position;
    return item;
}

bool pbnfc_chart_item_equal(const PbnfcChartItem *left,
                            const PbnfcChartItem *right)
{
    if (left == NULL || right == NULL) {
        return false;
    }
    return left->production == right->production &&
           left->alternative == right->alternative &&
           left->dot == right->dot && left->origin == right->origin &&
           left->position == right->position;
}

bool pbnfc_chart_init(PbnfcChart *chart, size_t position_count)
{
    size_t allocation_size;

    if (chart == NULL) {
        return false;
    }
    chart->sets = NULL;
    chart->set_count = 0U;
    if (position_count == 0U) {
        return true;
    }
    if (!size_mul_ok(position_count, sizeof(*chart->sets), &allocation_size)) {
        return false;
    }
    chart->sets = malloc(allocation_size);
    if (chart->sets == NULL) {
        return false;
    }
    (void)memset(chart->sets, 0, allocation_size);
    chart->set_count = position_count;
    return true;
}

void pbnfc_chart_free(PbnfcChart *chart)
{
    size_t position;

    if (chart == NULL) {
        return;
    }
    for (position = 0U; position < chart->set_count; ++position) {
        free(chart->sets[position].items);
    }
    free(chart->sets);
    chart->sets = NULL;
    chart->set_count = 0U;
}

size_t pbnfc_chart_set_count(const PbnfcChart *chart)
{
    return chart == NULL ? 0U : chart->set_count;
}

PbnfcChartSet *pbnfc_chart_set(PbnfcChart *chart, size_t position)
{
    if (chart == NULL || position >= chart->set_count) {
        return NULL;
    }
    return &chart->sets[position];
}

const PbnfcChartSet *pbnfc_chart_set_const(const PbnfcChart *chart,
                                            size_t position)
{
    if (chart == NULL || position >= chart->set_count) {
        return NULL;
    }
    return &chart->sets[position];
}

PbnfcChartInsertResult pbnfc_chart_insert(PbnfcChart *chart,
                                          const PbnfcChartItem *item)
{
    PbnfcChartSet *set;
    size_t index;

    if (chart == NULL || item == NULL || item->position >= chart->set_count) {
        return PBNFC_CHART_INSERT_ERROR;
    }
    set = &chart->sets[item->position];
    for (index = 0U; index < set->count; ++index) {
        if (pbnfc_chart_item_equal(&set->items[index], item)) {
            return PBNFC_CHART_INSERT_DUPLICATE;
        }
    }
    if (set->count == SIZE_MAX || !chart_set_reserve(set, set->count + 1U)) {
        return PBNFC_CHART_INSERT_ERROR;
    }
    set->items[set->count] = *item;
    ++set->count;
    return PBNFC_CHART_INSERTED;
}

size_t pbnfc_chart_set_size(const PbnfcChartSet *set)
{
    return set == NULL ? 0U : set->count;
}

const PbnfcChartItem *pbnfc_chart_set_at(const PbnfcChartSet *set,
                                         size_t index)
{
    if (set == NULL || index >= set->count) {
        return NULL;
    }
    return &set->items[index];
}
