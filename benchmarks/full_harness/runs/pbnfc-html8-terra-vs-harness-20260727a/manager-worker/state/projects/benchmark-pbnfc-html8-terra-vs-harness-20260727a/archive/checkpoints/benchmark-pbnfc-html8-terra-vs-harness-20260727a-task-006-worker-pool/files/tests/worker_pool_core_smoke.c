#include "worker_pool.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    pthread_mutex_t mutex;
    size_t calls[PBNFC_WORKER_POOL_SIZE];
    pthread_t thread_ids[PBNFC_WORKER_POOL_SIZE];
    bool have_thread_ids;
    bool fail_worker;
} Probe;

static int fail(const char *detail)
{
    (void)fprintf(stderr, "worker pool smoke: %s\n", detail);
    return 1;
}

static bool record_job(size_t worker_index, void *context)
{
    Probe *probe = (Probe *)context;
    pthread_t current = pthread_self();

    (void)pthread_mutex_lock(&probe->mutex);
    ++probe->calls[worker_index];
    if (!probe->have_thread_ids) {
        probe->thread_ids[worker_index] = current;
    } else if (!pthread_equal(probe->thread_ids[worker_index], current)) {
        probe->have_thread_ids = false;
    }
    (void)pthread_mutex_unlock(&probe->mutex);
    return !probe->fail_worker || worker_index != 3U;
}

int main(void)
{
    PbnfcWorkerPool pool = {0};
    Probe probe = {0};
    size_t index;

    if (pthread_mutex_init(&probe.mutex, NULL) != 0) {
        return fail("probe mutex initialization failed");
    }
    if (!pbnfc_worker_pool_init(&pool) ||
        pbnfc_worker_pool_worker_count(&pool) !=
            PBNFC_WORKER_POOL_SIZE) {
        pbnfc_worker_pool_free(&pool);
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("pool did not create exactly eight workers");
    }
    if (!pbnfc_worker_pool_run(&pool, record_job, &probe)) {
        pbnfc_worker_pool_free(&pool);
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("first generation failed");
    }
    for (index = 0U; index < PBNFC_WORKER_POOL_SIZE; ++index) {
        if (probe.calls[index] != 1U) {
            pbnfc_worker_pool_free(&pool);
            (void)pthread_mutex_destroy(&probe.mutex);
            return fail("first generation did not invoke every worker once");
        }
    }
    probe.have_thread_ids = true;

    if (!pbnfc_worker_pool_run(&pool, record_job, &probe) ||
        !probe.have_thread_ids) {
        pbnfc_worker_pool_free(&pool);
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("workers were not reused for the second generation");
    }
    for (index = 0U; index < PBNFC_WORKER_POOL_SIZE; ++index) {
        if (probe.calls[index] != 2U) {
            pbnfc_worker_pool_free(&pool);
            (void)pthread_mutex_destroy(&probe.mutex);
            return fail("second generation did not invoke every worker once");
        }
    }

    probe.fail_worker = true;
    if (pbnfc_worker_pool_run(&pool, record_job, &probe)) {
        pbnfc_worker_pool_free(&pool);
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("worker failure was not propagated");
    }
    probe.fail_worker = false;
    pbnfc_worker_pool_shutdown(&pool);
    pbnfc_worker_pool_shutdown(&pool);
    if (pbnfc_worker_pool_worker_count(&pool) != 0U) {
        pbnfc_worker_pool_free(&pool);
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("shutdown did not clear the worker count");
    }
    pbnfc_worker_pool_free(&pool);
    (void)pthread_mutex_destroy(&probe.mutex);
    return 0;
}
