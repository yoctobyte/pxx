---
track: N
prio: 55
type: bug
---

# A module-level ANNOTATED global is not visible in a keyword argument

```python
from dataclasses import dataclass, field

@dataclass
class R:
    evidence: list[str] = field(default_factory=list)

pe: dict[str, list[str]] = {}
pe["C"] = []
a = R(evidence=pe.get("C", []))     # error: undefined variable (pe)
print(len(a.evidence))
```

```
pascal26:9: error: undefined variable (pe)
  near:  R  evidence  pe >>>  get
```

The same name is visible everywhere else — `len(pe)`, `pe["C"] = []`, and a
plain call argument `f(pe.get("C", []))` all compile. Only the **keyword
argument of a class construction** fails to resolve it.

Dropping the annotation (`pe = {}`) compiles, so it is the ANNOTATED
module-level assignment specifically: that path registers the global somewhere
the dataclass keyword-argument parser does not consult.

Found while building a repro for
[[bug-nilpy-slice-of-variant-local-returned-is-unusable]]; unrelated to it.

## Fixed 2026-07-30 — and it was never about kwargs

Narrowed before fixing: `pe2 = pe` fails identically, and so does every
annotation kind including a bare `int`. The rule is "a module-level statement
whose RIGHT-HAND SIDE is trial-parsed cannot see an annotated global"; the
dataclass keyword argument in the original repro was simply the first such
statement in that file. `print(len(pe))` and `pe["C"] = []` are not trial-parsed,
which is why they looked fine and made this read as a kwarg bug.

Cause: `PyCollectModuleLocalsAST`'s annotated arm called `PyNoteLocalType`,
which records the name for the NEXT round's seeding loop, and nothing put it in
the CURRENT round's scratch scope. The "undefined variable" that followed is a
fatal Error, so the round that would have known the name never ran. The arm now
allocates it as well, exactly as the seeding loop does.

## Gate

The snippet above compiling and printing `0`, plus `make test-nilpy`.

## Log
- 2026-07-30 — resolved, commit 6eaacb53e.
