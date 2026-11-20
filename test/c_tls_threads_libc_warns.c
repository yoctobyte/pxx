/* __thread across threads: an initialised scalar, an array, a struct and a
   function-scope static. Statically linked, every thread has its own copy
   initialised from the image (gcc's output, x86-64/i386/aarch64/arm32 all
   match, measured 2026-11-19). Under --system-libs the thread is libc's: it
   shared the main block (x86-64 warned, i386 printed `main 9 30 50 14` in
   silence) until pthread_create was routed through palhostthread, which gives
   it a block of its own. That build now prints gcc's output too, with and
   without --threadsafe. (The file name keeps its history.)
   bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there */
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
