---
track: A
prio: 40
type: bug
---

# By-VALUE Variant parameters are miscompiled (silent garbage)

Found while building pylib (2026-07-19): `procedure show2(v: Variant)` —
by value, no const — compiles but the callee reads garbage: `show2(2)`
printed 4264384, and a variant VAR passed by value printed its TAG.
`const v: Variant` (by-ref) is correct and is what pylib uses. Either
implement true 16-byte by-value marshalling or reject by-value Variant
params with a diagnostic. Repro: scratchpad p7.pas pattern in the
feature-nilpy-list session log.

## Root cause (2026-07-19)

Two halves, both needed:

1. **Callee.** A Variant is 16 bytes, so `AllocParam` gives its slot
   POINTER size — the slot holds an address, never the value. But `IR_LEA`'s
   `skParam` disjunct ("this slot holds a pointer the caller passed") listed
   `IsRef / IsArray / frozen-string / tySet` and **not** `tyVariant`, so a
   by-value Variant param took `lea` of its own slot. `const v: Variant` was
   unaffected because the parser marks a const record/variant param `IsRef`,
   which the disjunct already covered — exactly why const worked and by-value
   did not. Missing in all six backends (x86-64, i386, aarch64, arm32,
   riscv32, xtensa).

2. **Caller.** `IRLowerCallArg`'s variant-boxing branch fired only for a
   NON-variant arg. A variant arg to a by-value Variant param therefore passed
   the caller's own address, giving reference semantics: a callee write would
   have leaked out once (1) was fixed. The branch now also fires for a variant
   arg when the param is not `IsRef`, routing it through a hidden temp. The
   synthesized `tmp := arg` lowers to the existing ARC-correct 16-byte
   `IR_VAR_STORE` (retain-before-release), and `tmp` is an ordinary variant
   local, so the epilogue's `PXXVarClear` releases it.

## Verification

`test/test_variant_byvalue_param.pas` (new, wired into `make test`): reads,
callee writes NOT reaching the caller, `var` still writing back, several
variant params in one call, literals, function return, float payload.
Byte-identical output on x86-64 / i386 / aarch64 / arm32.

Gate: `--tier full` GREEN (1523/1523, self-host fixedpoint) + self-host
byte-identical.
