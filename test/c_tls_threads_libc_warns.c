/* __thread across threads: an initialised scalar, an array, a struct and a
   function-scope static. Statically linked, every thread has its own copy
   initialised from the image (gcc's output, x86-64/i386/aarch64/arm32 all
   match, measured 2026-11-19). Under --system-libs on x86-64 the thread is
   libc's and shares the main block -- that build must WARN, which is what the
   test row checks. bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there */
#include <stdio.h>
#include <pthread.h>
__thread int tl = 7;
__thread int ta[3] = {1, 2, 3};
struct pt { int x, y; };
__thread struct pt ts = {4, 5};
static int bump(void) { static __thread int n = 10; return ++n; }
static void *th(void *a) {
    (void)a;
    int b1 = bump(); int b2 = bump();
    printf("thread %d %d %d %d %d\n", tl, ta[2], ts.y, b1, b2);
    tl = 9; ta[2] = 30; ts.y = 50;
    return 0;
}
int main(void) {
    pthread_t t;
    printf("main %d %d %d %d\n", tl, ta[2], ts.y, bump());
    pthread_create(&t, 0, th, 0); pthread_join(t, 0);
    printf("main %d %d %d %d\n", tl, ta[2], ts.y, bump());
    return 0;
}
