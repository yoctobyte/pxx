/* A C file pulled as a UNIT exercises what the C-PROGRAM driver had all along
   and the unit path did not: file-scope globals reserved and INITIALIZED, a
   function used before its definition, and a variadic function whose va_list
   comes from crtl's own <stdarg.h> rather than the host's.
   bug-cfront-unit-globals-unregistered. */
#include <stdarg.h>

static int bins[] = { 1, 2, 4, 8 };
static int base = 7;

static int later(int x);              /* prototype BEFORE the definition */

int cu_pick(int i)
{
    return bins[i] + base + later(i);
}

static int later(int x)
{
    return x * 10;
}

int cu_sum(int count, ...)
{
    va_list ap;
    int total = 0;
    int i;
    va_start(ap, count);
    for (i = 0; i < count; i++)
        total += va_arg(ap, int);
    va_end(ap);
    return total;
}
