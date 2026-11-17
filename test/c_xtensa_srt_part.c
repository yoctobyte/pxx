/* The second object of test/c_xtensa_srt_main.c. Its initialised globals are
   filled from its .init_array slot (pxx keeps them in .bss and fills them at
   run time); before, only main's object ran its initialisers and these read
   zero -- busybox's libbb/messages.c. feature-xtensa-objects-run-their-initialisers */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <stdarg.h>
char *part_dup(const char *s) { char *p = malloc(strlen(s) + 1); strcpy(p, s); return p; }
int part_fail_open(void) { return open("/nonexistent/pxx", O_RDONLY); }
FILE *part_stdout(void) { return stdout; }
const char *part_env(void) { const char *v = getenv("PXXT"); return v ? v : "(unset)"; }
int part_sum(int n, ...) { va_list ap; int s = 0; va_start(ap, n); while (n--) s += va_arg(ap, int); va_end(ap); return s; }
const char part_msg[] = "hello " "world";
const char *const part_ptrs[] = { part_msg, "two" };
int part_counter = 5;
struct part_row { const char *name; int v; };
const struct part_row part_rows[] = { { "a", 1 }, { "bb", 22 } };
