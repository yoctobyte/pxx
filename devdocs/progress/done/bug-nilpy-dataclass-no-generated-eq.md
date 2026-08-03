---
track: N
prio: 30
type: bug
status: done
owner: claude-AN
---

# `@dataclass` gets no generated `__eq__` — compares by identity instead of fields

Split out of
[[bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic]] (now
resolved for its four dispatch clusters), whose "Also measured" section
found this:

```python
from dataclasses import dataclass
@dataclass
class P:
    x: int
print(P(1) == P(1))     # CPython: True     pxx: False
```

CPython's `@dataclass` decorator generates `__eq__` comparing the declared
fields (and `__init__`/`__repr__`, but those already work per the sweep). pxx
compiles the decorator (init/field defaults land, per
`feature-nilpy-staticmethod-and-classmethod` and the songformatter ticket)
but does not synthesize `__eq__`, so `P(1) == P(1))` falls back to identity
comparison and is `False` where CPython says `True`.

Note this is a different root cause from the dispatch bug in the parent
ticket: a HAND-WRITTEN `__eq__` on an ordinary class IS honoured (see that
ticket's measured table — `__eq__`: yes/correct). Only the dataclass-generated
one is missing, i.e. the decorator's codegen needs to synthesize the method,
not that `__eq__` dispatch itself is broken.

## Suggested approach

Find wherever `@dataclass` field registration happens (`PyRegisterClassMembers`
per `feature-n-nilpy-ast-typing-module-scope`'s notes on the "dual
dataclass-table" path) and, when the class has no hand-written `__eq__`,
synthesize one that compares all declared fields — same shape as a
hand-written `def __eq__(self, other): return (self.f1, self.f2, ...) ==
(other.f1, other.f2, ...)` would produce, so it rides the already-working
`__eq__` dispatch path rather than needing a new one.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` regression
comparing a `@dataclass` equality result against CPython's actual output.

## Fixed 2026-08-03

`@dataclass` now synthesizes `__eq__` over the declared fields, as CPython's
decorator does. Two pieces, both mirroring the existing generated-ctor path:

- **Registration** (`PyRegisterClassMembers`, beside the `create` ctor):
  registered as an ordinary method, so the `==`/`!=` dispatch already in
  `ParseExpr` picks it up exactly like a hand-written one — no new dispatch
  machinery, which is what the ticket predicted. A **hand-written `__eq__`
  wins**: it is in the method table by the time this runs, and the synthesis is
  skipped (`FindUMeth(ci, '__eq__') < 0`). `PyDcEqProc[ci]` carries the proc
  index to the emitter.
- **Body** (`PyEmitDataclassEq`, beside `PyEmitDataclassCtor`):
  `Result := (self.f1 = other.f1) and ...` in declaration order.

A **class-typed field whose own class declares `__eq__` dispatches to it**
(`PyCallMeth1`), so a nested dataclass compares by value rather than by handle
— verified, and it is the case a naive field-by-field compare would have got
silently wrong. A field-less dataclass answers True, matching CPython's
comparison of two empty field tuples.

### Verified — the field-kind matrix is the point

`test/test_nilpy_dataclass_eq.npy` (new, both `test-nilpy` Makefile sites), 19
lines byte-identical to CPython: int/str/float/bool fields with each one
differing in turn; a nested dataclass field (equal and unequal); a field-less
dataclass; a `default_factory=list` field plus a defaulted str; `Optional`/
None-defaulted fields; `!=` in all four combinations; and a hand-written
`__eq__` overriding the generated one.

`tools/gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary).

### Found while gating, NOT caused by this — filed separately

`P1(3) in [P1(1), P1(3)]` is still False. Confirmed pre-existing by reproducing
with a HAND-WRITTEN `__eq__` on a plain class, which fails identically:
membership goes through pylib's `pycontains`, which compares boxed Variants and
never consults the element's class. Filed as
[[bug-nilpy-container-membership-ignores-the-eq-dunder]] — same family as
[[bug-nilpy-list-sort-ignores-lt-dunder-on-objects]], and blocked on the same
runtime-dispatch machinery.

Not modelled (CPython behaviour this fix does not reproduce): `@dataclass(eq=False)`,
and CPython setting `__hash__ = None` when it generates `__eq__`, which makes
instances unhashable. Neither is reachable through anything this frontend
currently supports.

## Log
- 2026-08-03 — resolved, commit 51563a1ec.
