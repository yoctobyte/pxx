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

---

## RESOLVED 2026-08-30 — B at **3.9**, and `sys.implementation` beside it

Owner's opening position was that the question is undecidable: *"we are not
cpython and lying about a version or making up a number sounds wrong."* That
instinct is right about **identity** and does not apply to `version_info`, and a
measurement changed the shape of the fork besides. Both below.

### `version_info` was never the identity field — `sys.implementation` is

`sys.version_info` means *which language level*, not *which product*. Python
separated the two in PEP 421 precisely because non-CPython implementations
exist: the language level goes in `version_info`, and the true identity in
`sys.implementation` (`.name`, and the implementation's OWN `.version`). Both
are absent from NilPy today — `sys.implementation` raises the same
AttributeError `version_info` does.

So the ticket's option C is not a rival to B. **It is the other field**, and
answering both is how you avoid claiming to be CPython while still answering the
question real code asks:

```
sys.implementation.name     = 'nilpy'
sys.implementation.version  = NilPy's own version
sys.version_info            = (3, 9, 0, 'final', 0)
sys.version                 = '3.9.0 (NilPy <ver>)'
sys.hexversion              = 0x030900F0
```

Nothing there is false. The version tuple states a language level we are
targeting for compatibility; the identity states what is actually running.

### Option A is not available: the subset is not an interval

Measured at HEAD, `.npy` probes, compiled and run:

| implemented | absent |
| --- | --- |
| f-strings (3.6), `1_000_000` (3.6) | **`yield from` (3.3)** |
| f-string `=` specifier (3.8) | **`async def` / `await` (3.5)** |
| `@dataclass` (3.7) | walrus `:=` (3.8) |
| dict `\|` merge (3.9), `str.removeprefix` (3.9) | positional-only `/` (3.8) |
| `*` / `**` unpacking, tuple comparison | `match` (3.10), `except*` (3.11), PEP 695 (3.12) |

Annotations are **erased**: `def f(x: ThisTypeDoesNotExist) -> AlsoNotReal`
compiles and runs. So `int | str` accepting is not 3.10 support and must not be
counted as any kind of coverage.

**Gaps at 3.3 and 3.5 alongside features at 3.9.** NilPy does not implement "up
to version X" — it implements the imperative-scripting core plus modern
conveniences, and lacks generator delegation, coroutines and pattern matching.
So *"claim the language level we implement"* names something that does not
exist, and no number is derivable from the feature set. That is what makes this
a judgment call, and it is why it was correctly filed as a U ticket rather than
worked as an N one.

### Option D is a charter violation, not a resting place

The ticket calls D *"a defensible resting place"*. It is not, by NilPy's own
rule in CLAUDE.md: **if code works on CPython, it must work on NilPy** — one
direction. `import sys; sys.version_info` works on CPython. A correctly-worded
catchable AttributeError makes the failure clean; it does not make it
conformant.

### Why 3.9 specifically

- Everything we lack **below** 3.9 fails as a **compile error with a file and a
  line**. NilPy is a compiler, not an interpreter, so over-claiming fails
  loudly and early rather than deep in a call stack — a materially better trade
  than the ticket assumed when it weighed "fails far from the version test".
- **3.10 is the first number that invites `match`**, the modern-branch
  construct we are most likely to meet and choke on. 3.9 is the last rung before
  that cliff.
- Claiming **lower does not help**, which is the non-obvious part: our gaps are
  not recent, so a legacy branch is no safer than a modern one — a 3.6-era
  fallback is *more* likely to reach for `yield from`, which we do not have.

### Two conditions, both aimed at "making up a number"

1. **The claim is tested, not asserted.** The probe set above becomes a NilPy
   test, so the number is backed by something that fails when it stops being
   true.
2. **The docs say it is a compatibility affordance, not a conformance claim** —
   the same discipline CLAIMS DISCIPLINE in CLAUDE.md applies to the two
   byte-identical claims. *"NilPy reports 3.9 so version-gated code selects a
   compilable branch; it does not implement all of 3.9, and the gaps are listed
   here."*

### Follow-on tickets

- [[feature-n-sys-version-info-implementation-and-the-probe-suite]] — the work.
- [[bug-n-yield-from-is-not-implemented]] and
  [[bug-n-async-def-and-await-are-not-implemented]] — surfaced BY the
  measurement and much bigger news than the version question. Both are ordinary
  Python that working CPython programs use, so by the charter they are N bugs,
  not divergences.
