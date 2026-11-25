/* The other object of c_link_return_from_main_runs_atexit_main.c: two handlers,
   run in reverse order of registration. */
#include <stdio.h>
#include <stdlib.h>
static void first(void) { printf("handler registered first runs last\n"); }
static void second(void) { printf("handler registered second runs first\n"); }
void register_handlers(void) { atexit(first); atexit(second); }
