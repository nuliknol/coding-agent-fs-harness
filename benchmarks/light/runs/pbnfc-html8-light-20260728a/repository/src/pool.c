#include "pool.h"

#include <stdlib.h>

static void *worker_main(void *arg)
{
    PoolWorkerArg *worker = (PoolWorkerArg *)arg;
    WorkerPool *pool = worker->pool;
    size_t index = worker->index;
    unsigned long seen = 0;

    for (;;) {
        pthread_mutex_lock(&pool->mutex);
        while (!pool->stopping && seen == pool->generation)
            pthread_cond_wait(&pool->work_ready, &pool->mutex);
        if (pool->stopping) {
            pthread_mutex_unlock(&pool->mutex);
            return NULL;
        }
        seen = pool->generation;
        pthread_mutex_unlock(&pool->mutex);

        if (pool->task != NULL && pool->ends[index] > pool->begins[index])
            pool->task(pool->context, index, pool->begins[index], pool->ends[index]);

        pthread_mutex_lock(&pool->mutex);
        pool->completed++;
        if (pool->completed == 8)
            pthread_cond_signal(&pool->done);
        pthread_mutex_unlock(&pool->mutex);
    }
}

int pool_start(WorkerPool *pool)
{
    size_t i;
    pool->generation = 0;
    pool->stopping = 0;
    pool->task_count = 0;
    pool->completed = 0;
    pool->task = NULL;
    pool->context = NULL;
    pool->begins = (size_t *)calloc(8, sizeof(*pool->begins));
    pool->ends = (size_t *)calloc(8, sizeof(*pool->ends));
    if (pool->begins == NULL || pool->ends == NULL) {
        free(pool->begins);
        free(pool->ends);
        return -1;
    }
    if (pthread_mutex_init(&pool->mutex, NULL) != 0)
        goto fail_arrays;
    if (pthread_cond_init(&pool->work_ready, NULL) != 0)
        goto fail_mutex;
    if (pthread_cond_init(&pool->done, NULL) != 0)
        goto fail_work;
    pool->initialized = 1;
    for (i = 0; i < 8; i++) {
        pool->worker_args[i].pool = pool;
        pool->worker_args[i].index = i;
        if (pthread_create(&pool->threads[i], NULL, worker_main, &pool->worker_args[i]) != 0) {
            size_t j;
            pthread_mutex_lock(&pool->mutex);
            pool->stopping = 1;
            pthread_cond_broadcast(&pool->work_ready);
            pthread_mutex_unlock(&pool->mutex);
            for (j = 0; j < i; j++)
                pthread_join(pool->threads[j], NULL);
            pthread_cond_destroy(&pool->done);
            pthread_cond_destroy(&pool->work_ready);
            pthread_mutex_destroy(&pool->mutex);
            pool->initialized = 0;
            goto fail_arrays;
        }
    }
    return 0;

fail_work:
    pthread_cond_destroy(&pool->work_ready);
fail_mutex:
    pthread_mutex_destroy(&pool->mutex);
fail_arrays:
    free(pool->begins);
    free(pool->ends);
    pool->begins = NULL;
    pool->ends = NULL;
    return -1;
}

int pool_run(WorkerPool *pool, size_t count, PoolTask task, void *context)
{
    return pool_run_range(pool, 0, count, task, context);
}

int pool_run_range(WorkerPool *pool, size_t begin, size_t end, PoolTask task, void *context)
{
    size_t i;
    size_t span = end - begin;
    pthread_mutex_lock(&pool->mutex);
    pool->task_count = span;
    pool->task = task;
    pool->context = context;
    pool->completed = 0;
    for (i = 0; i < 8; i++) {
        pool->begins[i] = begin + (span * i) / 8;
        pool->ends[i] = begin + (span * (i + 1)) / 8;
    }
    pool->generation++;
    pthread_cond_broadcast(&pool->work_ready);
    while (pool->completed != 8)
        pthread_cond_wait(&pool->done, &pool->mutex);
    pthread_mutex_unlock(&pool->mutex);
    return 0;
}

void pool_stop(WorkerPool *pool)
{
    size_t i;
    if (!pool->initialized)
        return;
    pthread_mutex_lock(&pool->mutex);
    pool->stopping = 1;
    pthread_cond_broadcast(&pool->work_ready);
    pthread_mutex_unlock(&pool->mutex);
    for (i = 0; i < 8; i++)
        pthread_join(pool->threads[i], NULL);
    pthread_cond_destroy(&pool->done);
    pthread_cond_destroy(&pool->work_ready);
    pthread_mutex_destroy(&pool->mutex);
    free(pool->begins);
    free(pool->ends);
    pool->begins = NULL;
    pool->ends = NULL;
    pool->initialized = 0;
}
