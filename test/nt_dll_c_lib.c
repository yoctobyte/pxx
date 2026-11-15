/* The C DLL test_nt_dll_built_by_pxx.pas calls: --os=nt --shared turns a .c
   file into nt_dll_c_lib.dll. Its non-static functions are the exports --
   and only its own: lib/crtl's bodies (strdup, div, ...) are compiled in but
   are the DLL's private copy. */
#include <string.h>
#include <stdlib.h>

static int counter = 40;

int c_next(void) { return ++counter; }
double c_scale(double x, int n) { return x * n; }
int c_dup_len(const char *s)
{
    char *d = strdup(s);
    int n = (int)strlen(d);
    free(d);
    return n;
}
static int c_hidden(void) { return counter; }
int c_peek(void) { return c_hidden(); }
