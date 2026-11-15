/* Threads from a --threadsafe OBJECT, created in a second object (Gibux s13).
   Three bugs between them: crtl's exported pthread_create captured the
   runtime's own weak libc import of the same name, so it re-entered itself and
   deadlocked on its registry lock; the thread's start read the creator's
   init image through a gs nothing had installed, and faulted; and
   PxxPthreadStart was a strong global in each object, so gcc refused the link.
   This half holds main; c_obj_thread_b.c creates and joins.
   bug-a-an-object-s-crtl-definition-captured-the-runtime-s-own-libc-import */
#include <stdio.h>
int start_threads(int n);
int main(void)
{
    printf("sum %d\n", start_threads(4));
    printf("again %d\n", start_threads(2));
    return 0;
}
