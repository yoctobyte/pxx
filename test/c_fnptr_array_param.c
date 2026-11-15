/* An array parameter of a FUNCTION POINTER decays to a pointer, as a named
   function's does: an array typedef (va_list is one on x86-64) or `T a[]`.
   The indirect call passed the array block by value, so the callee read
   garbage: dropbear's log hook `void (*)(int, const char *, va_list)` made the
   server segfault on its first log line.
   bug-c-an-array-parameter-of-a-function-pointer-does-not-decay */
#include <stdio.h>
#include <stdarg.h>
typedef struct { long a, b, c; } E;
typedef E A1[1];
static void f(int k, A1 x) { printf("%d %ld %ld\n", k, x[0].a, x->c); x->a = 9; }
static void (*h)(int, A1) = f;
typedef void (*ht)(int, A1);
static void vlog(const char *fmt, va_list ap) { char buf[100]; vsnprintf(buf, sizeof buf, fmt, ap); fputs(buf, stdout); }
static void (*hook)(const char *, va_list) = vlog;
static void logit(const char *fmt, ...) { va_list ap; va_start(ap, fmt); hook(fmt, ap); va_end(ap); }
static int sum3(int a[]) { return a[0] + a[1] + a[2]; }
static int (*ps)(int a[3]) = sum3;
int main(void)
{
    A1 v = {{1, 2, 3}};
    int t[3] = {4, 5, 6};
    ht g = f;
    h(5, v);
    printf("%ld\n", v[0].a);
    g(6, v);
    logit("x=%d s=%s\n", 42, "hi");
    printf("%d\n", ps(t));
    return 0;
}
