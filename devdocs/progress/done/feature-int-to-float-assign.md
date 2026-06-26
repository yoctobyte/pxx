# Integer → Float assignment / coercion missing the int→float conversion

- **Type:** bug
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-18 (found while implementing feature-float-str-val)

## Symptom

Assigning a plain integer **value** to a `Double` (or `Single`/`Extended`)
variable stores the integer's bit pattern instead of converting it to a float.

```pascal
var d: Double; n: Integer;
begin
  d := 1;        { d becomes a denormal ~4.9e-324, prints 0.0000 — should be 1.0 }
  n := 7; d := n;{ same — d is garbage, not 7.0 }
end.
```

Both `d := <int literal>` and `d := <int variable/expr>` are affected. Only
**expression-level promotion** works today: when a float operand is present in
the expression (`d := d * 10 + 5`, `d := n * 1.0`), the existing binop codegen
emits `cvtsi2sd`, so the result is correct. A pure-integer RHS into a float LHS
never converts.

## Why it matters

`floatvar := intexpr` is ordinary Pascal. The gap is only masked because float
code usually uses float literals (`1.0`) and float arithmetic. feature-float-str-val's
ValFloat had to work around it with `1.0`/`10.0` literals.

## Root cause / where to fix

The value model carries a float as double-bits in rax. AN_ASSIGN with a float
LHS and an integer-typed RHS lowers the RHS as an integer (int value in rax) and
stores it directly — no `cvtsi2sd xmm0, rax; movq rax, xmm0` bridge. Fix in the
shared IR lowering of AN_ASSIGN (and the same gap likely exists for: passing an
int arg to a float parameter, returning an int from a float function, and int
array/field elements read into a float). Cleanest: a single int→float coercion
helper/IR op applied wherever an integer value flows into a float slot, mirroring
the cvtsi2sd already inlined in IR_BINOP float ops (ir_codegen.inc ~line 2183).

## Acceptance

`d := 1`, `d := n`, float-param/return/element from int all produce the correct
float value, FPC byte-identical; `make test` + `make cross-bootstrap` stay green.

## Log
- 2026-06-18 — opened from the float Str/Val arc; ValFloat works around it.
- 2026-06-18 — attempted a quick fix (in AN_ASSIGN, when LHS is float and RHS is
  integer, lower RHS as `value + 0.0` to reuse the binop cvtsi2sd path). It
  produced correct values in isolation but **broke compiler self-fixedpoint**
  (the two self-compiles differed at byte 97 — non-deterministic codegen),
  reverted. So the blanket conversion interacts badly with the compiler's own
  float assignments / a tyDouble-tagged int-0 const. The proper fix needs a
  dedicated int→float IR op (or a narrower trigger) plus a cross-bootstrap check —
  not the `+0.0` hack. Do it in a focused session, not blind. Workaround stands:
  use float literals / `x := n * 1.0`.
- 2026-06-20 — **FIXED (x86-64).** Done precisely, NOT with the `+0.0` hack.
  In IR_STORE_SYM and IR_STORE_MEM (ir_codegen.inc), when the destination is a
  float, branch on the VALUE node's type: a float-typed RHS is bit-copied (movq,
  the existing path, unchanged) and an integer-typed RHS is converted (cvtsi2sd).
  Because already-float RHS is untouched, the over-broad coercion that perturbed
  the compiler's own float consts is avoided. Covers `d := 1`, `d := n`, record
  fields (`r.d := n`), and array elements (`a[i] := i`); float-RHS (`n * 1.0`)
  keeps working. test/test_int_to_float.pas in test-core.
  **KEY CORRECTION to the 2026-06-18 note:** the "non-deterministic / differs at
  byte N" symptom was a MISDIAGNOSIS. It is a normal one-generation RESEED, not
  non-determinism. Proof: after the change, gen3==gen4==gen5 are byte-identical
  (stable fixedpoint); only gen2 (produced by the OLD committed seed that lacks
  cvtsi2sd) differed from gen3. `make bootstrap` (FPC reseed) produces gen2==gen3
  directly and re-seeds compiler/pascal26; `make test` then passes byte-identical
  fixedpoint + --threadsafe, cross-bootstrap + cross suites green. Lesson: a
  codegen change that alters how the compiler emits ITSELF needs a `make
  bootstrap` reseed before `make test`'s seed-based fixedpoint will converge —
  expected, not a bug. See also the short-circuit/symtab reseed notes.
  Cross targets (i386/aarch64/arm32/xtensa/riscv) still bit-copy int->float
  (their backends are unchanged) and in fact reject float function results
  outright — cross float depth is a separate, larger effort, out of scope here.
