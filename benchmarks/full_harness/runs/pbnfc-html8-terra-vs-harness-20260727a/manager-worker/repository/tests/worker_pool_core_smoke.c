#include "worker_pool.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    pthread_mutex_t mutex;
    size_t calls[PBNFC_WORKER_POOL_SIZE];
    pthread_t thread_ids[PBNFC_WORKER_POOL_SIZE];
    unsigned long last_generation[PBNFC_WORKER_POOL_SIZE];
    bool have_thread_ids;
    bool fail_worker;
} Probe;

typedef struct {
    Probe *probe;
    unsigned long generation;
} GenerationContext;

typedef struct {
    PbnfcWorkerPool *pool;
} ShutdownContext;

static int fail(const char *detail)
{
    (void)fprintf(stderr, "worker pool smoke: %s\n", detail);
    return 1;
}

static bool record_job(size_t worker_index, void *context)
{
    GenerationContext *generation_context = (GenerationContext *)context;
    Probe *probe = generation_context->probe;
    pthread_t current = pthread_self();

    (void)pthread_mutex_lock(&probe->mutex);
    ++probe->calls[worker_index];
    probe->last_generation[worker_index] = generation_context->generation;
    if (!probe->have_thread_ids) {
        probe->thread_ids[worker_index] = current;
    } else if (!pthread_equal(probe->thread_ids[worker_index], current)) {
        probe->have_thread_ids = false;
    }
    (void)pthread_mutex_unlock(&probe->mutex);
    return !probe->fail_worker || worker_index != 3U;
}

static void *shutdown_thread(void *argument)
{
    ShutdownContext *context = (ShutdownContext *)argument;

    pbnfc_worker_pool_shutdown(context->pool);
    return NULL;
}

int main(void)
{
    PbnfcWorkerPool pool = {0};
    Probe probe = {0};
    GenerationContext generation_context = {&probe, 1UL};
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
    if (!pbnfc_worker_pool_run(&pool, record_job, &generation_context)) {
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
        if (probe.last_generation[index] != 1UL) {
            pbnfc_worker_pool_free(&pool);
            (void)pthread_mutex_destroy(&probe.mutex);
            return fail("first generation completion was not coordinated");
        }
    }
    probe.have_thread_ids = true;

    generation_context.generation = 2UL;
    if (!pbnfc_worker_pool_run(&pool, record_job, &generation_context) ||
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
        if (probe.last_generation[index] != 2UL) {
            pbnfc_worker_pool_free(&pool);
            (void)pthread_mutex_destroy(&probe.mutex);
            return fail("second generation completion was not coordinated");
        }
    }

    probe.fail_worker = true;
    generation_context.generation = 3UL;
    if (pbnfc_worker_pool_run(&pool, record_job, &generation_context)) {
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

    if (!pbnfc_worker_pool_init(&pool)) {
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("normal-shutdown pool initialization failed");
    }
    generation_context.generation = 4UL;
    if (!pbnfc_worker_pool_run(&pool, record_job, &generation_context)) {
        pbnfc_worker_pool_free(&pool);
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("normal-shutdown generation failed");
    }
    {
        pthread_t shutdown_threads[2];
        ShutdownContext shutdown_context = {&pool};
        size_t shutdown_index;
        int shutdown_threads_created = 0;
        int result;

        result = pthread_create(&shutdown_threads[0], NULL, shutdown_thread,
                                &shutdown_context);
        if (result == 0) {
            shutdown_threads_created = 1;
            result = pthread_create(&shutdown_threads[1], NULL,
                                    shutdown_thread, &shutdown_context);
            if (result == 0) {
                shutdown_threads_created = 2;
            }
        }
        if (shutdown_threads_created != 2) {
            pbnfc_worker_pool_shutdown(&pool);
            for (shutdown_index = 0U;
                 shutdown_index < (size_t)shutdown_threads_created;
                 ++shutdown_index) {
                (void)pthread_join(shutdown_threads[shutdown_index], NULL);
            }
            pbnfc_worker_pool_free(&pool);
            (void)pthread_mutex_destroy(&probe.mutex);
            return fail("concurrent shutdown thread creation failed");
        }
        (void)pthread_join(shutdown_threads[0], NULL);
        (void)pthread_join(shutdown_threads[1], NULL);
    }
    if (pbnfc_worker_pool_worker_count(&pool) != 0U) {
        pbnfc_worker_pool_free(&pool);
        (void)pthread_mutex_destroy(&probe.mutex);
        return fail("normal shutdown did not join all workers");
    }
    pbnfc_worker_pool_free(&pool);
    (void)pthread_mutex_destroy(&probe.mutex);
    return 0;
}
