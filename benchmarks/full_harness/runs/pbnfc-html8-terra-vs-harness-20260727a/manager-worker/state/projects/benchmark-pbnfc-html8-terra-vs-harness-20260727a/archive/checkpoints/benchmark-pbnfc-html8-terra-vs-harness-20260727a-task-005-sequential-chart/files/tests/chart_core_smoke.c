#include "chart.h"

#include <stdio.h>

static int fail(const char *detail)
{
    (void)fprintf(stderr, "chart smoke: %s\n", detail);
    return 1;
}

int main(void)
{
    PbnfcChart chart;
    PbnfcChartItem first;
    PbnfcChartItem second;
    PbnfcChartItem duplicate;
    const PbnfcChartSet *set;
    const PbnfcChartItem *item;

    if (!pbnfc_chart_init(&chart, 3U)) {
        return fail("chart initialization failed");
    }
    if (pbnfc_chart_set_count(&chart) != 3U ||
        pbnfc_chart_set(&chart, 3U) != NULL ||
        pbnfc_chart_set_const(&chart, 3U) != NULL) {
        pbnfc_chart_free(&chart);
        return fail("position sets were not exposed correctly");
    }

    first = pbnfc_chart_item_make(4U, 1U, 0U, 0U, 1U);
    second = pbnfc_chart_item_make(2U, 0U, 3U, 1U, 1U);
    duplicate = pbnfc_chart_item_make(4U, 1U, 0U, 0U, 1U);
    if (pbnfc_chart_insert(&chart, &first) != PBNFC_CHART_INSERTED ||
        pbnfc_chart_insert(&chart, &second) != PBNFC_CHART_INSERTED ||
        pbnfc_chart_insert(&chart, &duplicate) !=
            PBNFC_CHART_INSERT_DUPLICATE ||
        pbnfc_chart_set_size(pbnfc_chart_set_const(&chart, 1U)) != 2U) {
        pbnfc_chart_free(&chart);
        return fail("insert or duplicate handling failed");
    }

    set = pbnfc_chart_set_const(&chart, 1U);
    item = pbnfc_chart_set_at(set, 0U);
    if (item == NULL || !pbnfc_chart_item_equal(item, &first)) {
        pbnfc_chart_free(&chart);
        return fail("first insertion order was not retained");
    }
    item = pbnfc_chart_set_at(set, 1U);
    if (item == NULL || !pbnfc_chart_item_equal(item, &second) ||
        pbnfc_chart_set_at(set, 2U) != NULL) {
        pbnfc_chart_free(&chart);
        return fail("stable iteration was not retained");
    }
    if (pbnfc_chart_insert(&chart,
                           &(PbnfcChartItem){0U, 0U, 0U, 0U, 9U}) !=
            PBNFC_CHART_INSERT_ERROR ||
        pbnfc_chart_insert(NULL, &first) != PBNFC_CHART_INSERT_ERROR) {
        pbnfc_chart_free(&chart);
        return fail("invalid insert was not rejected");
    }

    pbnfc_chart_free(&chart);
    if (pbnfc_chart_set_count(&chart) != 0U) {
        return fail("chart was not reset on free");
    }
    return 0;
}
