# C: va_arg of any non-`int` type -> "invalid symbol in lea"

- **Type:** bug (Track C — C frontend desugar in `cparser.inc`; the failing
  guard is shared `ir.inc`).
- **Status:** done
- **Found:** 2026-06-26 writing the `lib/crtl` printf engine. Blocks the entire
  printf family: every `%s` (char*), `%x`/`%u` (unsigned), `%p` (void*) and
  `%ld` (long) needs a non-`int` `va_arg`.
- **Closed:** 2026-06-27

## Symptom
`va_arg(ap, T)` compiles only for `T == int`. Every other scalar type fails at
compile time:
```
$ pascal26 va.c out
pascal26:61: error: invalid symbol in lea ()
```
Reproduced for `unsigned int`, `long`, `char *`, `void *`, `unsigned long`.
Minimal repro:
```c
#include <stdarg.h>
static long f(int n, ...) {
  va_list ap; va_start(ap, n);
  long x = va_arg(ap, long);        /* char* / void* / unsigned all fail too */
  va_end(ap);
  return x;
}
int main(void){ return (int)f(1, 5); }
```
`va_arg(ap, int)` is fine (`test/cvarargs_int_b49.c` passes).

## Root cause (narrowed)
`cparser.inc` (~243) desugars `__builtin_va_arg(ap, T)` to
`*(T*)__pxx_va_arg_gp(&ap)` by building `AN_DEREF` **directly over the helper
`AN_CALL`**, tagging `ASTTk[deref] := T`:
```
node := AllocNode(AN_DEREF); ASTLeft[node] := callNode; ASTTk[node] := Ord(vt);
```
For `T = int` this lowers to a clean `IR_LOAD_MEM`. For an 8-byte / non-int `T`
the value-path lowering emits an `IR_LEA` whose operand is the call node (not a
symbol), tripping the verifier guard at `ir.inc:297` `Error('invalid symbol in
lea')`.

The equivalent **explicit** cast compiles and runs fine:
```c
extern void *get(void);
int main(void){ return (int)(*(long*)get()); }   /* ok */
```
The difference: the explicit form wraps the call in an `AN_PTR_CAST`
(`*(long*) ...`), the va_arg desugar omits it. Likely fix: wrap `callNode` in an
`AN_PTR_CAST` (to `T*`/tyPointer) before the `AN_DEREF`, matching the working
`*(T*)call()` shape — a Track C change in `cparser.inc`. (If the real defect is
the value-path `AN_DEREF` LEA for a non-int type over a non-symbol operand, that
is shared `ir.inc` and belongs to Track A — confirm which during the fix.)

## Acceptance
`va_arg(ap, T)` works for `int`, `unsigned`, `long`, and any pointer type;
`lib/crtl/src/stdio.c` `snprintf("%s/%x/%p", ...)` renders correctly.

## Resolution

- 2026-06-27 audit — **DONE / no longer reproducible.** Solved as a side effect
  of later Lua/stdio varargs work. Current `compiler/pascal26` compiles and runs
  the old `va_arg(ap, long)` repro, returning `5`, and a combined probe covering
  `unsigned int`, `char *`, and `void *` returns `42`. No `invalid symbol in lea`
  error remains.
