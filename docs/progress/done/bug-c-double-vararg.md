# C: double passed as a variadic arg reads 0

- **Type:** bug (Track C / shared codegen)
- **Found:** 2026-06-26 finishing C varargs.

`va_arg(ap, double)` returns 0. The internal call convention pushes each arg via
`push rax`, but a double is evaluated into xmm0, so its bits are never pushed into
the GP save area the variadic prologue captures. Integer/pointer/string varargs
work. Fix: for a variadic call, move a float arg's bits to rax before the push
(or pass it in the SysV xmm slot + save xmm in the prologue, which is already
reserved). lua uses %f in luaO_pushvfstring, so needed for correct float error
messages; %d/%s/%p already correct.

Repro:
```c
#include <stdarg.h>
int f(int n,...){ va_list ap; va_start(ap,n); double d=va_arg(ap,double); return (int)d; }
int main(void){ return f(1, 42.0); }   /* want 42, gets 0 */
}

## DONE 2026-06-26 (Track C)
Fixed in cparser __builtin_va_arg desugar: route a float `va_arg` through
`__pxx_va_arg_gp` (GP save area), not `__pxx_va_arg_fp`. The internal C variadic
call convention pushes every arg (a double is carried in rax by the value model)
and pops it into a GP register, so the callee prologue saves ALL varargs incl.
floats into the GP save area; the FP area is never filled. C variadic functions
are only ever called this way (libc-free), so the FP helper read unused slots ->
0. Now `va_arg(ap,double)` receives the value (repro f(1,42.5) -> d==42.5).
Self-host byte-identical (C-frontend desugar only).

NOTE: printf `%f`/`%g` still prints the `<float>` placeholder — that needs the
float-to-decimal formatting MATH, which is blocked separately by
bug-c-float-int-cast-and-spill (`(int)42.5`==0 and float subtract/compare in a
loop spills wrong). The vararg PLUMBING (this ticket) is done; the engine math is
that other ticket.
