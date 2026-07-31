---
track: A
prio: 55
type: bug
---

# A class's variant-typed field holding a managed string is not released on finalize — general, not Exception-specific

Found while measuring [[bug-nilpy-caught-exception-objects-are-never-freed]]:
fixing the exception OBJECT's own leak still left a smaller, separate slope in
the ticket's `int("notanumber")` row. Isolating it:

```python
class K:
    def __init__(self, s):
        self.msg = s   # s is an UNANNOTATED param -> field is tyVariant

i = 0
while i < 640000:
    e = K("x")         # constructed, reassigned, previous K released each iter
    i = i + 1
```

RSS grows linearly with the loop count. The SAME loop with `self.n = 5` (an int,
still through an unannotated param, so still a variant field) is **flat**. So
this is not "K's instance is never released" — the instance clearly is (the
int-field case proves the class's own release path works) — it is specifically
a **managed AnsiString held inside a variant-typed FIELD** that survives.

## Measured

| loop body | RSS at 40k | RSS at 640k | slope |
| --- | --- | --- | --- |
| `self.n = 5` (int, unannotated) | 284 KB | 284 KB | flat |
| `self.msg = s` (str via unannotated param) | 1308 KB | 20124 KB | ~31 B/iter |
| `raise ValueError()` (no message) | 1056 KB | 1056 KB | flat |
| `raise ValueError("x")` | 1568 KB | 20256 KB | ~32 B/iter |
| `e = ValueError("x")` (constructed, never raised) | 1308 KB | 19996 KB | ~32 B/iter |

The last three rows all funnel through the SAME thing: `Exception.msg` is a
plain `AnsiString` field, not a variant — so the leak is not confined to
variant-typed fields specifically, but `Exception.msg`'s assignment
(`msg := m;` in `Exception.Create`) and a NilPy class's inferred-variant field
assignment may share a release gap, or may be two symptoms of the same root
cause in the class-finalize walker. Not yet distinguished — see below.

## Where to look

`compiler/rtti_emit.inc`'s `ClassFieldNeedsFinal` already includes a
tyVariant-field arm (kind 5, "a variant slot can hold a managed string, a
promo, or a refcounted NilPy object; the walker clears it via PXXVarClear on
finalize") and a tyClass-field arm (kind 6) for NilPy — so the LAYOUT
DESCRIPTOR looks complete on paper. `PXXClassFinalize`
(`compiler/builtin/builtinheap.pas`) walks it and calls `PXXRecordRelease` for
kinds 1-3; check whether kind 5 (variant) is actually wired into that walk at
runtime, and whether `PXXVarClear`/`PyVarSlotClear` correctly frees a
`VT_STRING`-tagged payload (as opposed to only decrementing a refcounted
OBJECT payload) — the fact that a plain-int variant field leaks nothing, but a
plain-string one does, points at the string case specifically inside whichever
walker actually runs.

Also check `Exception.msg` specifically: it is declared as a plain
`AnsiString` field (not a variant), which is `FieldIsManaged` territory, not
`ClassFieldNeedsFinal`'s variant arm — a DIFFERENT code path from the `K.msg`
case above, so this ticket may turn out to be two separate bugs that happen to
look identical from the RSS slope alone. Measure both independently before
concluding they share a fix.

## Why it matters

Every NilPy class with a string field (the ordinary shape — `self.name = n`,
any dataclass-like record) leaks that field's storage on every reassignment or
scope exit of an instance holding one, in a tight loop. This is a much wider
blast radius than the exception-specific ticket that surfaced it.

## Gate

`make test-nilpy` + self-host byte-identical, plus an RSS-slope re-measurement
of the table above (40k/160k/640k, `/usr/bin/time -f %M`, per the debugging
playbook — a single run proves nothing): the string-field row must go flat,
matching the already-flat int-field row.

## RESOLVED — verified no longer leaks (smart sweep, 2026-07-31 @a3dda2e3c)

Fresh fixedpoint compiler at HEAD. 640k iterations of `e = K("hello")` with an
unannotated (tyVariant) string field, `e` used each iter (`total += len(e.msg)`,
output 3,200,000 confirms the loop ran and the construction was NOT dead-code-
eliminated): **peak RSS flat at ~1MB**. The variant field's managed string is
released on reassign/finalize now.

Fixed as part of the 2026-07-22/23 object-reclamation campaign (variant box
lifetime + managed-string reclamation, feature-nilpy-object-reclamation and the
container/owned-object frees). Same lineage that took the uforth microbench
552MB->flat.

## Log
- 2026-07-31 — resolved, commit a3dda2e3c.
