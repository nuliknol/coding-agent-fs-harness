#ifndef PBNFC_POOL_H
#define PBNFC_POOL_H

#include <pthread.h>
#include <stddef.h>

typedef void (*PoolTask)(void *context, size_t worker_index, size_t begin, size_t end);

typedef struct {
    struct WorkerPool *pool;
    size_t index;
} PoolWorkerArg;

typedef struct WorkerPool {
    pthread_t threads[8];
    pthread_mutex_t mutex;
    pthread_cond_t work_ready;
    pthread_cond_t done;
    unsigned long generation;
    int stopping;
    size_t task_count;
    size_t completed;
    PoolTask task;
    void *context;
    size_t *begins;
    size_t *ends;
    PoolWorkerArg worker_args[8];
    int initialized;
} WorkerPool;

int pool_start(WorkerPool *pool);
int pool_run(WorkerPool *pool, size_t count, PoolTask task, void *context);
int pool_run_range(WorkerPool *pool, size_t begin, size_t end, PoolTask task, void *context);
void pool_stop(WorkerPool *pool);

#endif
