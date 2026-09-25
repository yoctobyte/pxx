/* Variadic doubles that spill past the argument registers, on 32-bit targets.
 *
 * On riscv32 a variadic double takes an EVEN register pair, so after the format
 * in a0 the doubles land in a2:a3, a4:a5, a6:a7 and a fourth goes to the stack.
 * crtl's __pxx_va_arg_cross32 aligned by ADDRESS: once the reader crossed from
 * the register save area into the overflow area it padded the overflow pointer
 * whenever the address was not 8-aligned, and the caller pads by ARGUMENT-WORD
 * INDEX (as gcc does), so a fourth double read half of the third and printf
 * printed 5.30758e-315 -- no crash, no diagnostic. xtensa had the same reader.
 * The caller was correct throughout (disassembly, and IDF's newlib printf on
 * esp32c3 already printed these rows right).
 *
 * Each row puts the interesting argument somewhere a different pad decision
 * lands: 4 doubles then an int, 3 doubles then an int, a double then five ints
 * (all words past the regs are ints), alternating int/double (odd word index
 * forces a pad), long long, and a user function reading its own va_list. The
 * expected output is gcc's, identical on every target. */
#include <stdio.h>
#include <stdarg.h>

static double sumv(int n, ...)
{
    va_list ap;
    double s = 0;
    va_start(ap, n);
    for (int i = 0; i < n; i++) {
        if (i % 2) s += va_arg(ap, int);
        else s += va_arg(ap, double) * 100;
    }
    va_end(ap);
    return s;
}

int main(void)
{
    double a = 1, b = 2, c = 3, d = 4;
    int e = 77;
    printf("%g %g %g %g %d\n", a, b, c, d, e);
    printf("%g %g %g %d\n", a, b, c, e);
    printf("E %g %d %d %d %d %d\n", 1.5, 2, 3, 4, 5, 6);
    printf("%d %g %d %g %d %g %d %g\n", 1, 1.25, 2, 2.5, 3, 3.75, 4, 4.5);
    printf("%lld %d %lld %d %lld\n", 1234567890123LL, 7, -5LL, 8, 99LL);
    printf("%g\n", sumv(9, 1.0, 1, 2.0, 2, 3.0, 3, 4.0, 4, 5.0));
    return 0;
}
