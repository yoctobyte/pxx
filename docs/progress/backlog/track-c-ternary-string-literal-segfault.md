# C: ternary with two string-literal arms segfaults at runtime

- **Type:** bug (Track C / shared `ir.inc` AN_TERNARY lowering).
- **Found:** 2026-06-26 writing the printf engine (`upper ? "ABCDEF" : "abcdef"`).

## Symptom
A `cond ? "lit" : "lit"` whose arms are string literals compiles "ok" but
**segfaults** when the value is used:
```c
extern long write(int, const void *, unsigned long);
int main(void){
  int u = 1;
  const char *d = u ? "ABCDEF" : "abcdef";
  write(1, d, 6);                  /* SIGSEGV */
  return 0;
}
```

## Cause
`ir.inc` AN_TERNARY lowering retags a `tyString` result arm to managed
`tyAnsiString` (so the per-arm assignment coerces the frozen literal into a
managed temp and the load yields a real handle). That is correct for Pascal's
managed-default string model, but in **C mode** a string literal is a frozen
`char*`/`PChar`, not a managed AnsiString — coercing it through the ARC assign
path produces a garbage handle that the consumer dereferences -> crash.

The lowering needs a `CProgramMode` branch: a C string-literal ternary arm must
carry the literal's address (`char*`) like the rest of the C string model, not
go through the managed-string temp.

## Workaround in the meantime
Avoid string-literal ternary in C source; use `if/else`. `lib/crtl/src/stdio.c`
is written this way already.

## Acceptance
The repro prints `ABCDEF` and exits 0.
