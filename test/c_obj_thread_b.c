/* The creating half of c_obj_thread_a.c. */
#include <pthread.h>
#include <stdio.h>
static int slot[8];
static void *work(void *a) { int k = (int)(long)a; slot[k] = (k + 1) * 10; return (void *)(long)(k + 100); }
int start_threads(int n)
{
    pthread_t th[8];
    int i, sum = 0;
    for (i = 0; i < n; i++)
        if (pthread_create(&th[i], 0, work, (void *)(long)i) != 0) { printf("create %d failed\n", i); return -1; }
    for (i = 0; i < n; i++) {
        void *r = 0;
        if (pthread_join(th[i], &r) != 0) { printf("join %d failed\n", i); return -1; }
        sum += slot[i] + (int)(long)r;
    }
    return sum;
}
