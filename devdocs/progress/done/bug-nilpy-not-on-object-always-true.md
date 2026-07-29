---
track: N
prio: 80
type: bug
---

# `not <object>` was TRUE for every live object — silently wrong answers

```python
import re

def q(chord: str) -> tuple[str | None, str]:
    match = re.match(r'^([A-G][b#]?)(.*?)$', chord)
    if not match:
        return None, "unknown"
    return match.group(1), "ok"

print(q("Am"))    # CPython: ('A', 'ok')    pxx: (None, 'unknown')
```

Same for a plain user class:

```python
class K:
    def __init__(self, v: int): self.v = v
o = K(1)
if not o: print("NOT fired")   # CPython: silent.  pxx: prints.
```

`if o:` (no `not`) was correct all along, which is exactly what hid it.

**FIXED** (2026-07-29): `PyParseBoolNot` (pyparser.inc ~1483) fell through to
`AN_NOT` for any `tyClass` operand that is not a pylib container. `AN_NOT` is
Pascal's complement of the object HANDLE, which is never nil, so the result was
always non-zero, i.e. True. `not o` now lowers to `o = nil`, which is Python's
rule for an instance (truthy unless None).

This is the third member of the same family, after
`bug-nilpy-not-on-string-always-true` (complemented the string handle) and
`bug-nilpy-not-on-container-always-true` (complemented the list handle). The
container fix added a branch for pylib containers only and left every OTHER
class on the broken path.

## Why it matters

This is what made songformatter's key analysis return **wrong keys with no
error at all**. `_quality_bucket` opens with `if not match:` over an `re.match`
result, so every chord came back `(None, "unknown")`, every key scored
identically, and `ViolationCountDetector` ranked `ALL_KEYS` in insertion order —
`C, Cm, C dorian, ...` where CPython says `C mixolydian, F, E locrian, ...`.
No crash, no diagnostic, plausible-looking output.

Worth noting as a lesson for the tooling ticket
[[feature-debuggability-umbrella]]: a silent wrong ANSWER is the expensive
failure mode, not a segfault. It was only found by diffing a small probe against
CPython field by field.

## Repro / gate

The two snippets above. Then, in a `cp -r` of `~/songformatter`:

```python
from key_analysis import ViolationCountDetector
chords = ["Am", "G", "F", "C", "Dm", "E7", "Am", "G", "C", "F", "Bb", "A7", "Dm", "Gm", "C7", "F"]
def notes(c: str) -> list[str]: return []
r = ViolationCountDetector().analyze(chords, notes, sections=None)
print(r.to_text(True))
```

must match CPython exactly (it does now, character for character).

## Sweep still owed

The family rule is "truthiness keyed on a HANDLE". `PyMakeTruthy` and
`PyParseBoolNot` are two implementations of one question and have already
drifted three times. Fold them into one helper, and check every remaining
operand kind against CPython: `tyPointer`, a variant holding an object, a
bound-method value, `None`, a record, an interface.

## Log
- 2026-07-29 — resolved, commit 638e4a82e.
