---
track: N
prio: 70
type: feature
---

# NilPy: a def as a VALUE (procedure pointer)

Replaces the scope of `feature-nilpy-nested-def-as-value`, which was filed on
the belief that uforth needed CLOSURES. It does not — see
[[decide-nilpy-closure-model]] for the measurement that corrected it. 162 of
uforth's 205 inner defs capture nothing; what the corpus needs is the ability to
pass a function around at all.

## Repro

```python
def w_dup(vm: VM) -> None:
    vm.push(vm.peek())

vm.define_word("DUP", native=w_dup)     # w_dup as a VALUE — not supported
```

Calling works; referencing the name does not.

## Shape

pxx already has procedural types, `SymProcSig`/`SymElemProcSig` and
`AN_CALL_IND`, so this is frontend wiring rather than new codegen:

- `Callable[[VM], None]` in an annotation -> a procedural-typed symbol carrying
  the signature (`PyAnnTypeAt` already recognises the `callable` spelling; check
  what it produces).
- A bare def NAME in a value position -> the proc's address, tagged with its
  signature, instead of today's "call it or fail".
- A call through such a value -> `AN_CALL_IND` with that signature.
- The value must survive into a class FIELD and a container slot, since
  `native=` is stored on a Word object.

## Scope v1

The corpus is uniform enough to make v1 narrow: **arity 1, `-> None`** covers
186 of 205 natives (`(VM) -> None`). Support the general annotated signature if
it falls out; do not invent a first-class function TYPE system for it.

An escaping def that implicitly captures an enclosing local stays a hard ERROR
(zero corpus sites; keeps the closure fork open with no silent divergence).
Explicit by-value capture is [[feature-nilpy-default-args-on-nested-defs]].

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython — define, store in
a field and in a dict, pass as an argument, call through it, and two different
functions through the same slot — plus `--tier quick` + self-host
byte-identical.

## Log
- 2026-07-20 — resolved, commit b67724d7.
