#ifndef PBNFC_CHART_H
#define PBNFC_CHART_H

#include <stdbool.h>
#include <stddef.h>

/*
 * A chart item identifies one Earley state.  position is the chart set in
 * which the item is stored; origin is the position at which its production
 * began.  All fields participate in item identity, including position.
 */
typedef struct {
    size_t production;
    size_t alternative;
    size_t dot;
    size_t origin;
    size_t position;
} PbnfcChartItem;

typedef struct {
    PbnfcChartItem *items;
    size_t count;
    size_t capacity;
} PbnfcChartSet;

typedef struct {
    PbnfcChartSet *sets;
    size_t set_count;
} PbnfcChart;

typedef enum {
    PBNFC_CHART_INSERT_ERROR = -1,
    PBNFC_CHART_INSERT_DUPLICATE = 0,
    PBNFC_CHART_INSERTED = 1
} PbnfcChartInsertResult;

/* Initialize an item value without allocating ownership. */
PbnfcChartItem pbnfc_chart_item_make(size_t production,
                                     size_t alternative,
                                     size_t dot,
                                     size_t origin,
                                     size_t position);

bool pbnfc_chart_item_equal(const PbnfcChartItem *left,
                            const PbnfcChartItem *right);

/* Allocate position_count ordered sets. A zero-position chart is valid. */
bool pbnfc_chart_init(PbnfcChart *chart, size_t position_count);
void pbnfc_chart_free(PbnfcChart *chart);

size_t pbnfc_chart_set_count(const PbnfcChart *chart);
PbnfcChartSet *pbnfc_chart_set(PbnfcChart *chart, size_t position);
const PbnfcChartSet *pbnfc_chart_set_const(const PbnfcChart *chart,
                                            size_t position);

/*
 * Insert into the set selected by item->position. Items are retained in
 * insertion order and equal items are not appended a second time.
 */
PbnfcChartInsertResult pbnfc_chart_insert(PbnfcChart *chart,
                                          const PbnfcChartItem *item);

size_t pbnfc_chart_set_size(const PbnfcChartSet *set);
const PbnfcChartItem *pbnfc_chart_set_at(const PbnfcChartSet *set,
                                         size_t index);

#endif
