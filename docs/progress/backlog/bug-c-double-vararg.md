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
