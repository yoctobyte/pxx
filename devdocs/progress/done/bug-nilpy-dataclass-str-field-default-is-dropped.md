---
track: N
prio: 45
type: bug
---

# @dataclass: a `str` field's DEFAULT is silently dropped (becomes '')

```python
from dataclasses import dataclass

@dataclass
class D:
    a: str
    s: str = "t"
    i: int = 7
    f: float = 1.5
    b: bool = True

d = D("x")
print(repr(d.s), d.i, d.f, d.b)
```

```
pxx:     '' 7 1.5 True
CPython: 't' 7 1.5 True
```

The int, float and bool defaults sitting right beside it are all correct, which
is exactly what makes this hide: the class looks like defaults work.

Silent — no diagnostic, and `''` is a perfectly ordinary value, so it surfaces
far away as an empty name/path/label.

## Confirmed pre-existing

Built from `stable_linux_amd64/default/pinned` as well as HEAD: **both print
`''`**. Not a regression from the __repr__ work landed alongside this ticket
(the control removes the variable — a pinned BINARY, not a source revert).

## Where it is NOT — four candidates eliminated by measurement

This took four rebuilds to narrow, so the dead ends are recorded rather than
left for the next session to re-walk. `PXXDBG=n.ctorargs` prints every
construction's argument kinds and types and is the probe that answers this.

The call site builds the default as `[1]kind=2,tk=4` — an `AN_STR_LIT` tagged
**tyString** (frozen inline) — while the parameter it feeds is **tyAnsiString**
(managed). That mismatch is the fault. The question was who builds that node.

| candidate | eliminated by |
| --- | --- |
| `PyDcDefaultNode` PYDC_STR (pyparser.inc) | retagged it tyAnsiString → probe still printed tk=4; then made it emit an `AN_INT_LIT` marker → probe STILL printed kind=2. **Not in the path at all.** |
| `PyClsAttrNode` PYDC_STR (pyparser.inc) | retagged tyAnsiString → symptom unchanged; and its two call sites build ASSIGN statements, not args |
| the generated ctor body | `PXXDBG=a.ir:D.create` shows params `a` and `s` both `tk=23` storing to `tk=23` fields. **The ctor is correct** — the caller passes an empty string |
| the token capture | the class-attribute path (`NAME = "hello"`) uses byte-identical capture code and reads back correctly |

## The boundary — it is NOT "annotated str param with a default"

Varying the shape, every one of these is **correct** today:

```python
def g(a: int, s: str = "t") -> str: ...      # correct
def f(a, s="t"): ...                          # correct
class K:
    def __init__(self, a: int, s: str = "t"): ...   # correct
```

So `DefaultArgValueNode` (parser.inc:2649) builds a tyString literal for an
annotated `str` parameter in the ordinary cases and the conversion to a managed
AnsiString parameter works there. Only the **generated dataclass ctor's** call
site loses it. That is the remaining difference and where the next session
should start: what `PyClassCreate` does to a default argument that a plain
`ParseCall` does not.

## Why it was not fixed in the same session

The remaining suspects are `parser.inc` and the argument lowering in `ir*.inc`
— shared core files under the sole-A guard, and this session could not confirm
sole-A. Same block as the four tickets behind
`decide-sole-a-guard-for-unattended-sessions`.

## Gate when it lands

Extend `test/test_nilpy_dataclass_repr.npy`, which deliberately uses **no**
string defaults today and says why — pinning the wrong answer there would have
frozen this bug. Add a `str` default to its `Mixed` class and regenerate
`.expected` from CPython.

## 2026-08-09 — FIXED, and the earlier recon's four dead ends were all correct

`PyClassCreate` had a loop that filled every still-unsupplied STRING parameter
with a HARDCODED EMPTY LITERAL (`SOffset := 0; SLen := 0`), and it ran **before**
the dataclass-default loop. So it consumed the slot, and the default was never
consulted. Moving it to run LAST — after the dataclass defaults, filling only
what remains — is the whole fix.

**That is why the earlier session could prove three separate default-builders
were NOT in the path and still not find it.** `PyDcDefaultNode`, `PyClsAttrNode`
and `DefaultArgValueNode` were each markered with a distinctive `AN_INT_LIT` and
each failed to fire — all three answers were correct, because by then the
argument already existed. The eliminations were sound; the missing question was
"who filled this slot BEFORE any of them ran?"

The generalisable version, worth more than the fix: **when every candidate
producer is proved absent, stop looking for a producer and ask what CONSUMED the
slot.** The `n.ctorargs` probe showed an argument present with a plausible shape,
which reads as "someone built it wrongly" and not as "someone built it first".

Also confirmed by the same probe: the explicit and defaulted arguments are
*both* `AN_STR_LIT` with `tk=4`, so the node's type tag was never the difference
— an earlier hypothesis that cost a build to eliminate.

Verified against CPython: defaults given and omitted, several string defaults in
one class, a string default before and after other kinds, an EMPTY string
default (which must stay empty), and a hand-written `__init__` with a string
default as the control. `test/test_nilpy_dataclass_repr.npy` was also extended
with the string default its own header promised to add once this was fixed —
placed LAST in the class, since trailing string slots are what the bug consumed.
`gate.sh quick` GREEN.
