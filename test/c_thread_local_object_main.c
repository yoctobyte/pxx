#include <stdio.h>
#include <pthread.h>
__thread int tl_ext = 1;
extern __thread int tl_count;
int tl_work(int k);
int *tl_addr(void);
int tl_seed_init(void);
static int res[4]; static int *addr[4]; static int cnt[4];
static void *run(void *p) { long k = (long)p; tl_seed_init(); res[k] = tl_work((int)k); addr[k] = tl_addr(); cnt[k] = tl_count; return 0; }
int main(void) {
    pthread_t t[4]; long k; int d = 1;
    for (k = 0; k < 4; k++) pthread_create(&t[k], 0, run, (void *)k);
    for (k = 0; k < 4; k++) pthread_join(t[k], 0);
    for (k = 0; k < 4; k++) printf("thread %ld: %d count %d\n", k, res[k], cnt[k]);
    for (k = 1; k < 4; k++) if (addr[k] == addr[0]) d = 0;
    printf("distinct copies: %d\n", d);
    tl_seed_init(); printf("main: %d %d\n", tl_work(7), tl_count);
    return 0;
}
