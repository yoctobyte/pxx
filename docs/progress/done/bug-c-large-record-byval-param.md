# C: large (>16-byte) record passed by value gives garbage in the callee

- **Type:** bug (Track C / shared codegen)
- **Found:** 2026-06-26 while finishing C varargs.

A small record by-value param works (`struct {int a;}` -> 42). A 24-byte record
(`struct B {long a,b,c;}`) passed by value reads garbage in the callee:
`int g(struct B s){return (int)s.b;}` with `s.b=42` returns 200.

Repro:
```c
struct B { long a, b, c; };
int g(struct B s) { return (int)s.b; }      /* want 42, gets 200 */
int main(void){ struct B x; x.a=1; x.b=42; x.c=3; return g(x); }
```

Impact: blocks C-varargs **va_list passing** (lua's luaL_error ->
lua_pushvfstring(L, fmt, argp) hands a 24-byte va_list by value). Local va_arg
(int/long/ptr/string) already works; only passing the va_list to another function
hits this. Likely the by-value copy / SysV register-vs-stack classification for
records >16 bytes in the C call path.

## Root cause (2026-06-26)
Threshold is >8 bytes, not 24: 8B record param works, 16B+ reads garbage
(`struct{long a,b}` s.b=42 -> 120).

- C frontend allocates EVERY param `AllocParam(..., isRef:=False, ...)`
  (cparser.inc ~2242). A record param therefore has a slot of ParamSize=8
  (TARGET_PTR_SIZE) and is accessed INLINE by the callee: `s.b` -> `[slot+8]`.
- The CALLER, for a record arg with RecSize>8, takes the needTemp path
  (ir.inc ~1235): copies the record to a temp and passes the temp's ADDRESS
  (a pointer, 8 bytes). For RecSize<=8 it passes the record VALUE inline.
- Mismatch: for >8B the slot holds a POINTER (8 bytes), but the callee reads
  `[slot+8]` expecting record byte 8 -> reads past the pointer = stack garbage.
  At 8B the inline value fits the slot, so it works.

This is the System V struct-by-value-param ABI, which pxx's C frontend does not
model for records >8 bytes. Blocks va_list passing (24B va_list -> lua
luaO_pushvfstring).

### Fix design (by-ref + caller copy; true C by-value)
1. C frontend: a record param is `isRef:=True` so callee field access DEREFs
   (`[[slot]+off]`). C-only (cparser), so Pascal self-host stays byte-identical.
2. Caller (IRLowerCallArg): a C record arg ALWAYS copies to a hidden temp and
   passes &temp (not &caller's original) — true by-value (callee mutations stay
   local). Must distinguish a C by-value record param from a Pascal `var` record
   param (genuine by-ref, NO copy): needs a per-param "by-value record" marker
   (or gate on the callee being a C/CProgramMode proc) so the shared Pascal path
   is untouched.
3. Verify: 16B/24B record param == gcc; va_list passing == gcc; then lua RUNS.
