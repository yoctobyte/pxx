/* --system-libs: pthread_exit on the MAIN thread ends the process only once
 * every other thread is done, with status 0 and atexit run -- as glibc does.
 * It segfaulted (no __libc_start_main unwind buffer), and atexit was an
 * import libc.so does not have. bug-c-system-libs-pthread-exit-on-the-main-
 * thread-crashes, bug-c-system-libs-atexit-is-not-in-libc-so */
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
static void bye(void) { write(1, "atexit ran\n", 11); }
static void *worker(void *a) {
    usleep(100000);
    write(1, "worker done\n", 12);
    if (a) pthread_exit(0);           /* a non-main pthread_exit: libc's */
    return 0;
}
int main(void) {
    pthread_t t1, t2;
    atexit(bye);
    pthread_create(&t1, 0, worker, (void *)1);
    pthread_create(&t2, 0, worker, (void *)0);
    write(1, "main exits via pthread_exit\n", 28);
    pthread_exit(0);
    write(1, "not reached\n", 12);
    return 1;
}
