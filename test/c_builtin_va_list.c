/* `__builtin_va_list` with NO header, as NetBSD spells it in sys/ansi.h
   (`typedef __builtin_va_list __va_list;`) and its own <stdarg.h> uses it.
   pxx's va_list lives in crtl's <stdarg.h>, which such a unit never includes:
   "undeclared identifier 'va_list'". The preprocessor now pulls that header in
   at the first use. bug-c-builtin-va-list-needs-stdarg */
typedef __builtin_va_list __va_list;
typedef __va_list va_list;
#define va_start(ap, last) __builtin_va_start((ap), (last))
#define va_arg(ap, type)   __builtin_va_arg((ap), type)
#define va_end(ap)         __builtin_va_end((ap))
#define va_copy(d, s)      __builtin_va_copy((d), (s))

int printf(const char *, ...);

static long vsum(int n, va_list ap)
{
    long s = 0;
    while (n-- > 0)
        s += va_arg(ap, long);
    return s;
}

static long sum(int n, ...)
{
    va_list ap, cp;
    va_start(ap, n);
    va_copy(cp, ap);
    long a = vsum(n, ap);
    long b = vsum(n, cp);
    va_end(cp);
    va_end(ap);
    return a * 1000 + b;
}

static double mix(const char *fmt, ...)
{
    va_list ap;
    double d = 0;
    va_start(ap, fmt);
    for (; *fmt; fmt++)
        d += *fmt == 'i' ? va_arg(ap, int) : va_arg(ap, double);
    va_end(ap);
    return d;
}

int main(void)
{
    printf("%ld %.2f\n", sum(4, 1L, 2L, 3L, 4L), mix("idid", 1, 0.5, 2, 0.25));
    return 0;
}
