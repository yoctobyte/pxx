---
track: N
prio: 70
type: bug
blocked-by: []
summary: "sys.version_info throws at RUNTIME with a message admitting its own guard failed: 'the code guarding that (the flag its except-branch sets) let this call through anyway'. Two defects — the member is missing, and the compile-time guard meant to catch that does not fire. A guard that reports its own failure and continues is worse than no guard."
status: done
owner: agent-A
---

# A guard reports its own failure and lets the call through

- **Type:** bug — **Track N**. **Found:** 2026-08-18, jointly (frankonpiler-bf
  spotted the runtime throw; frank2-7e measured the boundary) while closing
  [[bug-n-from-sys-import-fails-while-import-sys-works]].
- **Measured at:** HEAD `7e7ed35d7` and pinned v349 — same on both.

## Repro

```python
import sys
print(sys.version_info)
```

```
Unhandled exception: Exception: this build has no sys.version_info: the import it
came from could not be resolved, and the code guarding that (the flag its
except-branch sets) let this call through anyway
```

## Two defects, and the second is the interesting one

1. **`sys.version_info` is not provided.** Other members are — `sys.argv` works,
   `os.getcwd()` works — so this is one absent member, not an unimplemented
   module. Providing it is a small decision with a question attached: what
   version does a NilPy build claim to be? Real code branches on it
   (`html5lib/_tokenizer.py:21` is `if version_info >= (3, 7)`), so answering
   too low silently selects legacy paths. **That part may want Track U.**

2. **The guard does not guard.** The message states plainly that a flag set in
   an except-branch was supposed to stop this call and did not. A guard that
   detects its own failure, says so, and proceeds anyway is worse than no guard:
   it converts a compile-time refusal into a runtime crash in the user's
   program, and it has clearly been failing long enough for someone to write the
   sentence describing it.

Defect 2 is independent of defect 1 — the guard would still be broken for the
next unprovided member. Fix it first; it is the one that generalises.

---

## Resolved 2026-08-27 — defect 2. Defect 1 split to Track U.

### The guard was not failing. There was no guard.

The ticket read the message literally and concluded a flag set in an
except-branch was being ignored. Reading the code says otherwise: `sys.<unknown>`
in `pyparser.inc` (~11229) deliberately emits a raise — *"an attribute this sys
does not have — raise, as CPython does"* — and it is right to. It just emitted
it through **`pyoptional_missing`**, the raise built for a *different* concept:
a name bound to None because its optional import could not be resolved.

So one raise served two concepts, and its sentence described only the first. For
`import sys`, which resolves perfectly and which no except-branch guards, every
clause of that sentence is false. **The message was not reporting a failure; it
was borrowed.** That is worse than the ticket's reading, not better: a sentence
describing a mechanism that is not there is what sent this ticket looking for a
broken flag.

### The half the message hid

The wording was the visible defect. The load-bearing one is the **class**:
`pyoptional_missing` raises a bare `Exception`, so

```python
try:
    sys.version_info
except AttributeError:
    ...
```

— the idiomatic probe for an optional member, and the shape real code uses —
**walks straight past it and the program dies**. Measured at pinned v379: the
witness test does not print a caught message, it aborts on line 1. CPython
raises `AttributeError` there, so this was a program CPython accepts and runs
that NilPy could not, which is the exact definition of an N bug.

### The fix

- **`pylib.pas`** — `pyattr_missing(owner, attr)`, raising
  `AttributeError.Create('module ''sys'' has no attribute ''version_info''')`.
  CPython's class, and CPython's sentence character for character.
- **`pyparser.inc`** — `PyMakeAttrMissingCall`, and the `sys.<unknown>` site
  routed to it. Deliberately does **not** set `PyExprHadOptionalMissing` and
  does **not** call `PySkipOptionalMissingChain`: both belong to the
  optional-import concept. `sys` is a real module, a name assigned from it is a
  real variant, and `.major` on the result must compile to an ordinary runtime
  attribute access — CPython raises at the first step here too, so there is
  nothing to swallow.

`pyoptional_missing` keeps its message, which is true of the callers it still
has (`pyparser.inc` ~14812/15230/15241, the unresolved-import family).

### Defect 1 — `sys.version_info` is still absent, deliberately

Split to **[[decide-nilpy-what-version-does-sys-version-info-claim]]** (Track U,
prio 62), exactly as this ticket predicted it would need to be. The
implementation is fifteen minutes; the *number* is a product claim, because real
code branches on it (`if sys.version_info >= (3, 7)`) and any answer silently
steers third-party libraries down one path or the other. Nothing in the tree
claims a Python version today, so this sets the precedent. Escalate, don't
guess.

What ships today is a defensible resting place rather than a gap: the raise is
catchable and correctly worded, so a program that probes copes and a program
that reads it unguarded dies with CPython's own message.

### Found while testing, NOT fixed here

`getattr(sys, name)` does not compile — `error: undefined variable (sys)`, i.e.
`sys` as a *value*. That is
[[bug-n-a-resolved-module-member-as-a-value-is-an-undefined-variable]], already
filed at prio 70; the witness test spells its probe without `getattr` and says
why in a comment.

### Gate

`make compiler/pascal26` (fixedpoint `52e7b3b95cb5`), `tools/gate.sh quick`
GREEN, and a witness row `test_nilpy_missing_module_attr_is_attributeerror` in
`test-core` whose `.expected` is CPython's own output. At pinned v379 it does not
merely differ — it aborts on the first row, which is the whole point.

**`compiler/builtin/pylib.pas` changed, so this needs a PIN.**

## Log
- 2026-08-27 — resolved, commit 0ecd624e6.
