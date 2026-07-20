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

## The worst manifestation, found 2026-07-20 after for-in landed

Concatenating a loop variable — a variant — onto a string produces GARBAGE
BYTES, not a wrong number:

```python
xs = ["a", "b"]
acc = ""
for v in xs:
    acc = acc + v
print(acc)          # CPython: ab      pxx: \0\001\340\341,~
```

With a string on the left the binop lowers as string concatenation and reads
the variant's 16 bytes as a string handle. This is the same missing unbox as
below, but it is the shape a corpus hits FIRST, because "iterate a list of
strings and build a string" is the most ordinary loop there is. The dict
variant of it (`for k in d: ks = ks + k`) is identical.

Note this got easier to hit, not newly broken, when for-in landed: before
that there was no way to get a variant into a loop variable without an
explicit subscript.

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

## Log
- 2026-07-20 — resolved, commit 8bd1ac4c.
