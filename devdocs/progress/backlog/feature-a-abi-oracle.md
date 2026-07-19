---
track: A
prio: 60
type: feature
---

# ABI oracle: backends consult it, and stop reading Syms[]

Design: `devdocs/dev/type-identity-as-substrate.md` item 4.
Depends on [[feature-a-typeref-handle]].

## The break being fixed

`IRTk` is a bare kind and identity rides `IRA`/`IRB`/`IRC` positionally per
opcode. That is not enough to emit code, so backends reach around the IR into
frontend data:

```pascal
(Syms[symIdx].Kind = skParam) and (Syms[symIdx].IsRef or ...)
```

The IR claims to be the substrate but a backend cannot be written against the IR
alone.

## Shape

- **portable, carried in the IR:** 16-byte managed variant; class #7.
- **per-target, NOT in the IR:** register vs memory, 4 vs 8 bytes, hidden-dest
  vs `rax`. Freezing these into the IR breaks cross-compilation — this is the
  thing to get right.

A per-target oracle answers `PassBy(t)` / `ReturnVia(t)` / `SlotHoldsPointer(t)`.
**Backends consult the oracle and never touch `Syms[]`** — that clause is the
enforceable invariant, and is greppable in review.

## Cleans up

The "param slot holds a pointer" rule is written 8 times and 3 copies disagree
(see [[bug-a-param-pointer-rule-divergence]]). `AN_CALL` and `AN_VIRTUAL_CALL`
decide returns independently, which is why a `def` returning str works and a
method crashes ([[bug-nilpy-method-returning-str-garbage]]).

CAUTION: `RetViaHiddenDest` does NOT cover `tyAnsiString` — a managed string
returns a heap handle in a register. The oracle must not assume
"aggregate" == "hidden dest".

## Success metric

Adding one new pass-by-pointer / return-via-dest type kind currently needs edits
at **9 independent sites**. After this it must need **one**. If it still takes
six backend edits, this failed regardless of how clean it reads.
