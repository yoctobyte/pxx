# C: string literal assigned to a `char *` points at the Pascal length-prefix

- **Type:** bug (high impact for lua/sqlite)
- **Track:** C (C frontend) / shared IR-codegen
- **Opened:** 2026-06-25
- **Found-by:** lua import — files assign `const char *` from literals everywhere
  (statname tables, cached error messages, etc.).

## Symptom

```c
int len(const char *s){int n=0;while(*s){n++;s++;}return n;}
int main(void){ const char *a = "hello"; return len(a); }   /* gcc 5, pxx 1 */
```

`a[0]` reads **5** (the LENGTH of "hello"), `a[1]` reads **0**. So `a` points at
the 8-byte Pascal length prefix, not char 0. Yet a string literal used DIRECTLY
as a call argument is correct: `len("hello world")` == 11 — that path already
lands on char 0.

## Root cause

`InternStr` (emit.inc) stores literals as `[8-byte length][chars][NUL]`.
`Strs[si].Offset` points at the length prefix; `Offset + 8` at char 0. The
generic `AN_STR_LIT -> IR_CONST_STR` value (ir.inc ~1649, codegen
ir_codegen.inc ~1429) emits `Offset` (the prefix). The DIRECT call-argument /
write / index paths compensate with their own `Offset + 8` (ir_codegen.inc
1704/2220/2803, and the AN_STR_LIT index special-case at ir.inc ~684–690), so
those are right; the pointer-assignment STORE path uses the bare value and lands
on the prefix. This is the known `pc:='literal'` gap noted in
project_pchar_conv_dynlib_done.

## Fix sketch (needs care — multiple paths)

A clean fix makes a C string literal's VALUE consistently the char-0 address and
removes the per-context `+8` compensations, OR keeps the prefix base and adds the
`+8` in the assignment-store path. The trap: a naive `Offset+8` in the generic
IR_CONST_STR codegen (gated on CProgramMode via IRIVal) fixes assignment but
DOUBLE-counts the call-argument path (which already adds 8) — verified: it
regresses `len("hello world")` from 11 to 3 (points at char 8). So the call-arg
`+8` must be removed in the same change. Per-backend (x86-64 first; i386/aarch64/
arm32/riscv32/xtensa all have their own IR_CONST_STR). Harmonize ALL the
AN_STR_LIT paths (value / index / call-arg / write) in one pass and add a fixture
covering: assigned-then-deref, direct call arg, index `s[i]`, and write/printf.
