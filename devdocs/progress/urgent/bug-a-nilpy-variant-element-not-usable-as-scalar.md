---
track: A
prio: 85
type: bug
---

# NilPy: a list/dict ELEMENT cannot be used as a scalar — silent garbage or IR_UNSUPPORTED

Found 2026-07-19 building [[feature-nilpy-dict]]. **Pre-existing and
list-wide** — dict just made it visible; every repro below uses only the list
feature that shipped earlier. Filed Track A: the missing piece is a
variant->scalar unbox in the shared IR lowering (`ir.inc`), not frontend
syntax.

## Repros — the SILENT ones first

```python
def f() -> int:
    xs = [5, 6]
    return xs[0]          # CPython 5   -> pxx  -401796328

def g() -> int:
    xs = [5, 6]
    b = xs[1]
    return b              # CPython 6   -> pxx  1     <-- the variant TAG

def h() -> int:
    xs = [5, 6]
    a: int = xs[0]        # explicit annotation does not help
    return a              # CPython 5   -> pxx  garbage
```

And the loud one:

```python
xs = [5, 6]
print(xs[0] + 1)
```
```
error: IR_UNSUPPORTED: frontend could not lower AST node (kind 5)
```
(kind 5 = AN_BINOP.)

## What works, and why that hid it

`print(xs[0])` is CORRECT — the writeln path has its own variant handling
(`EmitWriteVariant`), so every test and demo written so far printed elements
and never consumed one. The moment an element is returned, assigned to a
typed name, or used in arithmetic, it is wrong.

## The gap

A container element is a `Variant` (16-byte tag+payload; list and dict slots
are both `TPyVarRec`). There is no IR operation that reads a variant AS a
scalar: `defs.inc` has `IR_VAR_STORE`, `IR_VAR_BINOP` and `IR_VAR_BOX` — box
but no unbox. So:

- a scalar context gets the raw 8 bytes (payload or tag, depending on path)
  instead of the value,
- and `AN_BINOP` over a variant operand has no lowering at all, hence
  IR_UNSUPPORTED.

`IR_VAR_BINOP` exists for variant-OP-variant, which is why variant LOCALS
(test_nilpy_variant.npy) work; the element case never reaches it because the
element is a call result, not a variant lvalue.

## Shape

Add the unbox: `IR_VAR_UNBOX` (variant addr + target TTypeKind -> scalar in
the target's register class), then lower to it wherever a tyVariant value
lands in a scalar context — return, typed assignment, arithmetic operand,
argument to a non-variant parameter. Tag mismatch policy is a real decision
(CPython would raise TypeError; the frozen model may prefer a coerce) — if it
is not obvious when implementing, file a `decide-` rather than guessing.

## Why the priority

This is the difference between "NilPy has lists and dicts" and "NilPy can
USE lists and dicts". [[feature-nilpy-corpus-uforth]] is blocked behind it in
practice: uforth reads from `vm.stack`, `vm.dict` and `vm.xt_table` on almost
every line, and today every one of those reads is silently wrong outside a
print.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, and all four
repros above matching CPython.
