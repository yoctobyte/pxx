---
track: A
prio: 30
type: bug
---

# NilPy: a bitwise op on a FLOAT variant truncates instead of raising TypeError

Found 2026-07-20 while adding variant bitwise operators for the uforth drive.

`EmitVarBinOp` (ir_codegen.inc) lowers variant arithmetic in two paths: an
integer path and a double path, chosen by the runtime tag. The new bitwise
operators (`& | ^ << >>`) are integer operators, so on the DOUBLE path they
truncate both operands to Int64 and apply the op, producing VT_INT64.

Python raises `TypeError: unsupported operand type(s) for &: 'float' and 'int'`.

## Why it shipped this way

Emitting a runtime type error needs machinery `EmitVarBinOp` does not have (it
is hand-emitted x86-64 with no error-raise helper in scope). Truncation is at
least consistent with how `div`/`mod` ALREADY treat a double operand in the
same routine — those deviate from Python too, deliberately, with Pascal
semantics.

Unreachable from the uforth corpus, which masks integers behind `isinstance`
guards, so this is a latent correctness gap rather than an active wrong answer.

## Fix when picked up

Give the variant-arithmetic path a way to raise, then make float-operand
bitwise raise TypeError. That same helper would let `div`/`mod`-by-zero and
other variant type errors stop deviating as well, so it is worth more than
this one bug.

## Note

x86-64 only: `EmitVarBinOp` has no counterpart in the other backends, so
variant bitwise ops are not available cross-target at all yet.

## Log
- 2026-07-23 — resolved, commit 64d86ef3.
