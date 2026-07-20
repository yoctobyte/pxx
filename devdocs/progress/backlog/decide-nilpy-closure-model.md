---
track: U
prio: 20
type: idea
---

# DECIDE (DEFERRED): which closure model for NilPy?

**Status 2026-07-20: deferred with evidence, not answered — and it does not
block anything.** Filed earlier the same day claiming closures-as-values was the
uforth blocker. That claim was WRONG and is corrected below; the fork is real
but nothing in the corpus can observe it, so building for it now would be
speculative.

## What the corpus actually does

Measured over `/home/rene/projects/uforth/uforth.py` (214 inner defs):

| fact | number |
| --- | --- |
| inner defs capturing NOTHING from the enclosing scope | 162 / 205 |
| inner defs defined inside a loop | **0** |
| inner defs whose capture is written explicitly as a default arg | the rest |

The natives are uniform: `def w_x(vm: VM) -> None`, all inside one
`build_base_vm(...)`, registered as `vm.define_word("+", native=w_plus)`.

Where uforth genuinely closes over something, it already spells the capture
by-value at definition time, using Python's own idiom:

```python
def _field(v, _offset=offset):     # the `i=i` trick
```

So the author wrote around late binding. **By-value at definition IS what the
source asks for**, and no site exists where A and B differ.

## Correction to the earlier filing

The earlier note said "52 inline calls vs ~197 value uses ⇒ closures are the
blocker". The ~197 are `native=w_x` KEYWORD ARGUMENTS — real value uses, but of
functions that capture nothing. A second scanner bug inflated the capture count:
free-name analysis that did not treat a nested `for i, v in ...` target as the
inner def's OWN local, so `w_dot_s` looked like it captured `i` and `v` when
both are its own loop variables.

## Recommendation when this is picked up

Unchanged in substance, and still cells:

- **cells (option B)** remain the right end state — correct late binding, and
  `nonlocal` falls out free.
- The cheap path is still hybrid: a def whose name is only ever CALLED keeps
  today's trailing by-value parameters (shipped, gated, zero heap); a def used
  as a VALUE gets a closure record. Cells then change only WHERE the captured
  value lives, not the call path, so B is an increment on that representation.
- NilPy computes its capture set before frame layout (`PyCollectLocalsAST` trial
  parse, `PyQueueNestedDef` free-name scan), which is the part that makes cells
  expensive in most compilers. That cost is already paid here.

## What to do INSTEAD, now

Implicit capture by an ESCAPING def stays a hard error — zero corpus sites, so
it costs nothing and keeps this fork open with no silent divergence. The real
corpus needs are, in order:

1. [[feature-nilpy-function-values]] — a def as a VALUE (procedure pointer).
2. [[feature-nilpy-keyword-args]] — `f(x, native=g)`, 196 sites.
3. [[feature-nilpy-default-args-on-nested-defs]] — `def _f(v, _off=offset)`,
   which is explicit by-value capture and needs no closure machinery.
