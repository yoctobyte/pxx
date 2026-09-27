/* An initialised thread-local starts at its initialiser in EVERY thread, not
   only in main.
   bug-c-an-initialised-thread-local-reads-zero-in-every-thread-but-main

   The initialiser is a store in main's prologue, and before the fix it reached
   only the main thread's block: a child read 0 where gcc reads 5. Now each
   initialiser store also writes an init image, and every new block starts as a
   copy of it (TLS_SLOT_INIT_IMAGE in the compiler).

   Each row is chosen so that an obvious wrong mechanism fails it:
     child-x=5       the initialiser, not 0 (the bug itself, and the default)
     child-y=0       an UNinitialised neighbour still starts at 0, so the copy
                     did not smear anything into it
     child-z=-7      a second initialised variable at a different offset
     grandchild-x=5  a thread made by a thread gets the image too, so the
                     pointer is handed on and not only read from main's block
     main-x=6        main changed its copy BEFORE creating the thread, and the
                     child still saw 5: a copy of main's CURRENT block would
                     print child-x=6, which is why main writes 6 first
   The expected output is gcc's, and identical on every target that gives
   threads a block. */
#include <stdio.h>
#include <pthread.h>

__thread int x = 5;
__thread long y;
__thread int z = -7;

static void *grandchild(void *a) {
    printf("grandchild-x=%d\n", x);
    return 0;
}

static void *child(void *a) {
    pthread_t g;
    printf("child-x=%d\n", x);
    printf("child-y=%ld\n", y);
    printf("child-z=%d\n", z);
    x = 50;
    pthread_create(&g, 0, grandchild, 0);
    pthread_join(g, 0);
    return 0;
}

int main(void) {
    pthread_t t;
    x = 6;
    y = 2;
    pthread_create(&t, 0, child, 0);
    pthread_join(t, 0);
    printf("main-x=%d\n", x);
    return 0;
}
