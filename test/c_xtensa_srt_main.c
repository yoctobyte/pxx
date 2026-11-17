/* Two xtensa objects built --shared-runtime plus the runtime object
   (lib/crtl/include/pxx/runtime_all.h): crtl state crosses objects -- errno
   set in one is read in the other, stdout is one FILE, environ one array,
   and a malloc in one is freed in the other. Plus setjmp/longjmp and varargs
   in both, and the other object's initialised globals.
   tools/check_xtensa_shared_runtime.py
   feature-xtensa-shared-runtime-objects-link */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <setjmp.h>
#include <stdarg.h>
char *part_dup(const char *s);
int part_fail_open(void);
int part_sum(int n, ...);
FILE *part_stdout(void);
const char *part_env(void);
extern const char part_msg[];
extern const char *const part_ptrs[];
extern int part_counter;
struct part_row { const char *name; int v; };
extern const struct part_row part_rows[];
static jmp_buf jb;
int main(int argc, char **argv)
{
    char *d = part_dup("shared");
    int r = part_fail_open();
    int e = errno;
    printf("dup %s open %d errno %d same-stdout %d env %s sum %d\n", d, r, e,
           part_stdout() == stdout, part_env(), part_sum(3, 4, 5, 6));
    free(d);
    printf("[%s] [%s] %d %s%d\n", part_msg, part_ptrs[1], part_counter,
           part_rows[1].name, part_rows[1].v);
    if (setjmp(jb) == 0) longjmp(jb, 9);
    return argc + 1;
}
