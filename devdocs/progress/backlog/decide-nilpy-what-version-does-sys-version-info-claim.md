---
track: U
prio: 62
type: decision
blocked-by: []
summary: "sys.version_info is absent, and providing it is a product claim, not an implementation detail: real code branches on it to select code paths, so any number we answer silently steers third-party libraries. Decide what version a NilPy build reports — and whether it reports a CPython version at all."
---

# What version does `sys.version_info` claim?

Split out of [[bug-n-a-guard-reports-its-own-failure-and-lets-the-call-through]]
on 2026-08-27, which fixed that ticket's defect 2 (the raise now says
`AttributeError: module 'sys' has no attribute 'version_info'`, CPython's own
sentence, and is catchable by `except AttributeError`). Defect 1 — the member
being absent — is a **decision**, and the ticket said so when it was filed.

## Why this is Track U and not just work

The implementation is fifteen minutes: a `pysys_version_info` returning a
5-tuple, plus `sys.version` and `sys.hexversion` beside it for the same reason.
The number in it is the whole question, because **real code branches on it and
takes a different path depending on the answer**:

```python
if sys.version_info >= (3, 7):   # html5lib/_tokenizer.py:21
```

Answer too low and libraries silently select legacy paths — the failure mode is
a *working program taking the wrong branch*, not an error. Answer too high and
they select paths using features we may not have, and the failure is a crash
somewhere unrelated to the version test.

Nothing in the tree claims a Python version today (`grep -rn version_info
compiler/ lib/` finds nothing), so this sets a precedent rather than following
one.

## The fork

| option | what `sys.version_info` answers | consequence |
| --- | --- | --- |
| **A. claim the language level we implement** | e.g. `(3, 8, 0, 'final', 0)` | honest, and the number is a promise we can point at a test suite for. Libraries take pre-3.9 paths even where we would handle the modern one. |
| **B. claim a high recent version** | e.g. `(3, 12, 0, 'final', 0)` | libraries take the modern paths, which are usually the ones we actually implement (NilPy was built against modern CPython). Anything we are missing fails far from the version test. |
| **C. answer NilPy's OWN version** | e.g. `(0, 1, 0, 'final', 0)` | truthful about what is running and immediately breaks every `>= (3, x)` test in the wild — i.e. the opposite of the point. |
| **D. keep raising** | AttributeError, as now | a program that probes with `except AttributeError` copes; one that reads it unguarded dies with a clear message. No silent wrong branch, ever. |

## Recommendation

**B, at the language level we can defend** — a recent 3.x, chosen so that the
modern branch of a version test is the branch we implement, since that is
empirically the branch NilPy was written against. It converts the failure mode
from *silently wrong* into *loudly missing*, which is the trade this repo makes
everywhere else. If that is too strong a claim to make yet, **D is a real
answer** and is what ships today — the raise is now catchable and correctly
worded, so it is a defensible resting place rather than a gap.

Whatever is chosen, `sys.version`, `sys.hexversion` and `sys.version_info` must
agree, and the number belongs in ONE constant that all three read.

## Adjacent, and NOT part of this decision

`sys.maxsize` and `sys.byteorder` are absent too and are plain FACTS about the
target (`2**63 - 1`, `'little'`) with no product claim attached. They can land
under Track N without waiting for this.
