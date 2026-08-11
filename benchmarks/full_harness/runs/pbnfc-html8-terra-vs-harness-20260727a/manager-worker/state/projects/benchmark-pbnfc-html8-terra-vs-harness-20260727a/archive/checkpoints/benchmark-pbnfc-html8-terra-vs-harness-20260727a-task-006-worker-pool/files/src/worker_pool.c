#include "worker_pool.h"

#include <string.h>

static void *worker_main(void *argument)
{
    PbnfcWorkerPoolStart *start = (PbnfcWorkerPoolStart *)argument;
    PbnfcWorkerPool *pool = start->pool;
    const size_t worker_index = start->worker_index;
    unsigned long observed_generation = 0UL;

    for (;;) {
        PbnfcWorkerPoolJob job;
        void *context;
        bool succeeded;

        (void)pthread_mutex_lock(&pool->mutex);
        while (!pool->shutdown_requested &&
               observed_generation == pool->generation) {
            (void)pthread_cond_wait(&pool->work_available, &pool->mutex);
        }
        if (pool->shutdown_requested) {
            (void)pthread_mutex_unlock(&pool->mutex);
            return NULL;
        }
        observed_generation = pool->generation;
        job = pool->job;
        context = pool->job_context;
        (void)pthread_mutex_unlock(&pool->mutex);

        succeeded = job(worker_index, context);

        (void)pthread_mutex_lock(&pool->mutex);
        if (!succeeded) {
            pool->job_failed = true;
        }
        ++pool->completed_count;
        if (pool->completed_count == pool->thread_count) {
            (void)pthread_cond_signal(&pool->work_complete);
        }
        (void)pthread_mutex_unlock(&pool->mutex);
    }
}

bool pbnfc_worker_pool_init(PbnfcWorkerPool *pool)
{
    size_t index;
    int result;

    if (pool == NULL) {
        return false;
    }
    (void)memset(pool, 0, sizeof(*pool));
    result = pthread_mutex_init(&pool->mutex, NULL);
    if (result != 0) {
        return false;
    }
    result = pthread_cond_init(&pool->work_available, NULL);
    if (result != 0) {
        (void)pthread_mutex_destroy(&pool->mutex);
        return false;
    }
    result = pthread_cond_init(&pool->work_complete, NULL);
    if (result != 0) {
        (void)pthread_cond_destroy(&pool->work_available);
        (void)pthread_mutex_destroy(&pool->mutex);
        return false;
    }
    pool->synchronization_initialized = true;

    for (index = 0U; index < PBNFC_WORKER_POOL_SIZE; ++index) {
        pool->starts[index].pool = pool;
        pool->starts[index].worker_index = index;
        result = pthread_create(&pool->threads[index],
                                NULL,
                                worker_main,
                                &pool->starts[index]);
        if (result != 0) {
            pbnfc_worker_pool_shutdown(pool);
            pbnfc_worker_pool_free(pool);
            return false;
        }
        pool->thread_count = index + 1U;
    }
    return true;
}

bool pbnfc_worker_pool_run(PbnfcWorkerPool *pool,
                           PbnfcWorkerPoolJob job,
                           void *context)
{
    bool succeeded;

    if (pool == NULL || job == NULL || !pool->synchronization_initialized) {
        return false;
    }
    (void)pthread_mutex_lock(&pool->mutex);
    if (pool->shutdown_requested ||
        pool->thread_count != PBNFC_WORKER_POOL_SIZE || pool->running) {
        (void)pthread_mutex_unlock(&pool->mutex);
        return false;
    }
    pool->job = job;
    pool->job_context = context;
    pool->completed_count = 0U;
    pool->job_failed = false;
    pool->running = true;
    ++pool->generation;
    (void)pthread_cond_broadcast(&pool->work_available);
    while (pool->completed_count != pool->thread_count) {
        (void)pthread_cond_wait(&pool->work_complete, &pool->mutex);
    }
    succeeded = !pool->job_failed;
    pool->running = false;
    (void)pthread_mutex_unlock(&pool->mutex);
    return succeeded;
}

void pbnfc_worker_pool_shutdown(PbnfcWorkerPool *pool)
{
    size_t index;
    size_t thread_count;

    if (pool == NULL || !pool->synchronization_initialized) {
        return;
    }
    (void)pthread_mutex_lock(&pool->mutex);
    if (pool->shutdown_requested) {
        thread_count = pool->thread_count;
        (void)pthread_mutex_unlock(&pool->mutex);
    } else {
        pool->shutdown_requested = true;
        (void)pthread_cond_broadcast(&pool->work_available);
        thread_count = pool->thread_count;
        (void)pthread_mutex_unlock(&pool->mutex);
    }
    for (index = 0U; index < thread_count; ++index) {
        (void)pthread_join(pool->threads[index], NULL);
    }
    pool->thread_count = 0U;
}

void pbnfc_worker_pool_free(PbnfcWorkerPool *pool)
{
    if (pool == NULL || !pool->synchronization_initialized) {
        return;
    }
    pbnfc_worker_pool_shutdown(pool);
    (void)pthread_cond_destroy(&pool->work_complete);
    (void)pthread_cond_destroy(&pool->work_available);
    (void)pthread_mutex_destroy(&pool->mutex);
    (void)memset(pool, 0, sizeof(*pool));
}

size_t pbnfc_worker_pool_worker_count(const PbnfcWorkerPool *pool)
{
    if (pool == NULL || !pool->synchronization_initialized ||
        pool->shutdown_requested) {
        return 0U;
    }
    return pool->thread_count;
}
