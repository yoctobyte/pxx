# Integer → Float assignment / coercion missing the int→float conversion

- **Type:** bug
- **Status:** backlog
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
