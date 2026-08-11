#ifndef PBNFC_WORKER_POOL_H
#define PBNFC_WORKER_POOL_H

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>

#define PBNFC_WORKER_POOL_SIZE 8U

struct PbnfcWorkerPool;

typedef struct {
    struct PbnfcWorkerPool *pool;
    size_t worker_index;
} PbnfcWorkerPoolStart;

/*
 * A job is invoked exactly once by each persistent worker for every
 * pbnfc_worker_pool_run call.  worker_index is stable for the lifetime of
 * the pool and is in the range [0, PBNFC_WORKER_POOL_SIZE).
 */
typedef bool (*PbnfcWorkerPoolJob)(size_t worker_index, void *context);

typedef struct PbnfcWorkerPool {
    pthread_t threads[PBNFC_WORKER_POOL_SIZE];
    PbnfcWorkerPoolStart starts[PBNFC_WORKER_POOL_SIZE];
    pthread_mutex_t mutex;
    pthread_cond_t work_available;
    pthread_cond_t work_complete;
    PbnfcWorkerPoolJob job;
    void *job_context;
    size_t thread_count;
    size_t completed_count;
    unsigned long generation;
    unsigned long completed_generation;
    bool job_failed;
    bool running;
    bool shutdown_requested;
    bool synchronization_initialized;
} PbnfcWorkerPool;

/* Create exactly PBNFC_WORKER_POOL_SIZE persistent workers. */
bool pbnfc_worker_pool_init(PbnfcWorkerPool *pool);

/*
 * Run one generation and wait until every worker has completed its callback.
 * Only one generation may be active at a time.  A false callback result is
 * reported as false after all workers have still been allowed to finish.
 */
bool pbnfc_worker_pool_run(PbnfcWorkerPool *pool,
                           PbnfcWorkerPoolJob job,
                           void *context);

/* Stop and join all workers. Safe to call more than once. */
void pbnfc_worker_pool_shutdown(PbnfcWorkerPool *pool);

/* Release synchronization resources after shutdown. */
void pbnfc_worker_pool_free(PbnfcWorkerPool *pool);

size_t pbnfc_worker_pool_worker_count(const PbnfcWorkerPool *pool);

#endif
