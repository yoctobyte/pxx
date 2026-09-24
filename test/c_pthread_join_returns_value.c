/* SPDX-License-Identifier: 0BSD */
/* pthread_join hands back the start routine's return value (POSIX). crtl used
 * to write 0 whatever the thread returned. retval is pre-filled with 12345 so
 * a join that writes nothing cannot pass as the null worker's legitimate 0.
 * Joins run in reverse order so a value cannot come from the wrong slot by
 * position. Expected output is gcc -pthread's, measured 2026-09-25. */
#include <stdio.h>
#include <pthread.h>

static int values[4] = {42, 7, -1, 1000};

static void *worker(void *arg) {
    int *p = (int *)arg;
    return (void *)(long)(*p * 2 + 1);
}

static void *null_worker(void *arg) {
    (void)arg;
    return 0;
}

int main(void) {
    pthread_t t[4];
    void *r;
    int i;
    for (i = 0; i < 4; i++) pthread_create(&t[i], 0, worker, &values[i]);
    for (i = 3; i >= 0; i--) {
        r = (void *)12345;
        pthread_join(t[i], &r);
        printf("thread %d returned %ld\n", i, (long)r);
    }
    pthread_create(&t[0], 0, null_worker, 0);
    r = (void *)12345;
    pthread_join(t[0], &r);
    printf("null worker returned %ld\n", (long)r);
    pthread_create(&t[0], 0, worker, &values[0]);
    printf("join with NULL retval: %d\n", pthread_join(t[0], 0));
    printf("PJ-DONE\n");
    return 0;
}
