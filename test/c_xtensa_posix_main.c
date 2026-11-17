/* main(argc, argv) from a windowed xtensa posix object's process entry
   (app_main at .text+0): the Linux initial stack, the environment, atexit,
   and main's result as the exit status. tools/check_xtensa_posix_main.py.
   feature-xtensa-posix-objects-get-a-process-entry */
#include <stdio.h>
#include <stdlib.h>
static void bye(void) { printf("atexit ran\n"); }
int main(int argc, char **argv)
{
    const char *h = getenv("PXXT");
    atexit(bye);
    printf("argc %d argv1 %s env %s\n", argc, argc > 1 ? argv[1] : "-", h ? h : "(none)");
    return 3;
}
