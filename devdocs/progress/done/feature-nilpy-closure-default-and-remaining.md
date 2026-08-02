---
track: N
prio: 45
type: feature
---

# NilPy: remaining uforth walls past ~88% (closure-captured defaults, then exec)

Hangs off [[feature-nilpy-corpus-uforth]]. As of 2026-07-21 the wall is
uforth.py:3829 — the first parse error is now this far in, after ~90 features
landed this session (267 -> 3829, ~88% of the 4357-line file).

## The current wall (3829)

```python
def _compile_name_xt(vm2: VM, target: Word = w) -> None:
```

A parameter default that is a CAPTURED VARIABLE (`w` from the enclosing scope),
Python's by-value loop-variable capture idiom. NilPy requires a CONSTANT default
(None/bool/int/str). This is closure capture expressed as a default: the
nested-def capture machinery (PyQueueNestedDef) already captures enclosing
locals the body reads as trailing params — a non-constant default that names an
enclosing local could be folded into that same capture, evaluated at def time.

## What still remains after it

The wall has been bouncing between nested defs (3994 -> 3967 -> 3846 -> 3829) as
each is fixed, because uforth registers ~200 native-word bodies as nested defs
and the first failing one changes. Expect a tail of small per-def issues of the
same kind already handled (variant subscript/slice, dynamic attrs, method
chains) plus:

- **Closure-captured parameter defaults** (this wall).
- **Variant slice ASSIGN** — `mem[a:b] = src` where mem is a variant holding
  bytes (a first attempt was reverted for a runtime bug; the READ works).
- **exec() actually running** — [[feature-lib-pyexec]]. exec() compiles as a
  stub; the native-word PYTHON blocks it should evaluate do not run. This is the
  milestone-3 subsystem and the real remaining work for a WORKING uforth.

## Status honestly

The file PARSES ~88% of the way. Reaching a compiled binary needs the tail of
per-def fixes above; reaching a RUNNING uforth needs pyexec. Both are scoped;
neither is a single edit.

## Re-checked 2026-07-31 — two of three items now fixed, closing what's fixed

- **Closure-captured parameter defaults** (the 3829 wall itself): FIXED.
  Re-measured the exact repro shape (`def inner(target=w): ...` where `w`
  is an enclosing local) directly against CPython — matches.
- **Variant slice ASSIGN** (`mem[a:b] = src`): FIXED. Verified both a
  literal-bytes RHS and a slice-of-the-same-variant RHS
  (`mem[a:b] = mem[c:d]`); byte content matches CPython exactly. (Noted in
  passing, unrelated to this ticket: pxx's bytearray `print()` shows
  `b'...'`, CPython shows `bytearray(b'...')` — a separate, minor,
  non-blocking repr-formatting gap.)
- **exec() actually running**: NOT a residual bug — checked `EvalPyStmts`
  (pyeval.pas) directly, and it is a DELIBERATE, already-documented design
  decision: "locals live in pyeval's own arrays... the `l`/`g` dict
  argument is accepted for API compatibility... but is not the backing
  store... never read back by the host." A plain `exec("x = 5", env);
  print(env["x"])` genuinely does not write back into `env` (confirmed:
  prints the ORIGINAL value, not the exec'd result) — this diverges from
  CPython's real contract (which does write module-level assignments back
  into the passed globals dict), but it is a conscious, already-accepted
  scope boundary from `feature-lib-pyexec` (resolved separately, commit
  a366d5945), not something to reopen here. uforth's own actual usage goes
  through host function calls (`push`/`pop`/`store`), which already work
  correctly and are what that ticket's "feature-complete... across the
  censused corpus" claim is measured against.

This ticket's own two items are done; the corpus's ACTUAL remaining walls
(now past line 3829) are tracked in `feature-nilpy-corpus-uforth`'s own
2026-07-31 recheck (next wall found near line 3887, not yet isolated).

## Log
- 2026-07-31 — resolved, commit f8dd8453b.

## 2026-08-02 — scope correction on the "closure-captured defaults: FIXED" claim

Re-measured while sweeping function semantics. That claim is correct but reads
wider than it is: the def-time re-parse implementing it lives in
`PyNestedDefClosureValue`, so it runs only when a nested def is materialised as
a closure VALUE. A def that is merely CALLED never reaches it:

```python
def outer():
    w = 7
    def inner(b=w):
        return b
    return inner()      # -> None, not 7
```

On the ordinary call path every non-constant default still silently becomes
None — including `b=[]`, `b={}`, `b=()` and any name. Filed as
[[bug-nilpy-non-constant-parameter-defaults-silently-become-none]] (prio 70).
This ticket stays resolved; only the scope of its claim is narrowed here, so the
next reader does not take "defaults are fixed" at face value.
