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

## Gate

The snippet above compiling and printing `0`, plus `make test-nilpy`.
