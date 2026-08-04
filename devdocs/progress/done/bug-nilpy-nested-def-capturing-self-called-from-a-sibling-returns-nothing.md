---
track: N
prio: 50
type: bug
summary: "Inside a METHOD, a nested def that captures self returns nothing when called from a SIBLING nested def — `C().run()` prints an empty line where CPython prints 17. Pre-existing (identical on pinned), and needs no lambda to reproduce."
status: done
owner: claude-AN
---

# A nested def capturing `self` returns nothing when a sibling nested def calls it

- **Type:** bug (NilPy — SILENT wrong value) — **Track N**
- **Found:** 2026-08-04, while fixing
  [[bug-nilpy-lambda-over-a-capturing-nested-def-does-not-compile]]. Filed
  separately because it needs no lambda at all, which makes it far easier to
  work on than the shape it was found through.
- **Pre-existing:** identical output on `stable_linux_amd64/default/pinned`.

## Repro — no lambda anywhere

```python
class C:
    def __init__(self):
        self.n = 7
    def run(self):
        def draw(v):
            return v + self.n
        def use():
            return draw(10)
        return use()
print(C().run())          # CPython 17    pxx: an empty line
```

Silent: no diagnostic, no crash, and the printed value is empty rather than
wrong-but-numeric, which suggests the result is reaching the caller as a
string-shaped or absent value rather than as a mis-added integer.

## What is NOT the problem

- **Not the capture list.** `PXXDBG=n.caps` reports it correctly:
  ```
  PXXDBG n.caps def C.run.draw caps=self
  PXXDBG n.caps def C.run.use  caps=self
  ```
  Both nested defs capture `self`, which is right.
- **Not nested-def-calls-sibling in general.** The identical shape in a plain
  FUNCTION works and prints 11:
  ```python
  def outer():
      def add(v):
          return v + 1
      def use():
          return add(10)
      return use()
  ```
- **Not `self` capture in general.** A nested def capturing `self` and called
  DIRECTLY from the method body works.

So it is specifically: **inside a method**, one nested def calling a **sibling**
nested def that captures `self`. The two candidates are the forwarding of the
captured `self` at that inner call site, and the return type inferred for `use`
(an empty print is what a wrongly-string-typed result looks like — see
[[project_string_conversion_shape_blindspot_pattern]]); measure both before
choosing, `PXXDBG=n.locals` and `a.ir:C.run.use` will show which.

## Why it matters now

The lambda spelling of this same shape used to fail to COMPILE, so it was loud.
Since `bug-nilpy-lambda-over-a-capturing-nested-def-does-not-compile` was fixed
it compiles and produces `None` — i.e. it now behaves exactly like the
non-lambda spelling above. That is consistency, and it is the right trade (the
fix made seven other lambda shapes correct), but it does mean this shape is
silent in both spellings until this ticket is done.

## Gate

A `.npy` diffed against CPython: the repro; the lambda spelling of it; the plain
FUNCTION control; the direct-call control; and a nested def capturing an
enclosing method LOCAL (rather than `self`) called from a sibling, to see
whether `self` is special or any method-level capture is.


## Resolved 2026-08-04 — it is narrower AND wider than filed

Filed hours earlier from the shape it was found through. Both halves of that
framing were wrong, and measuring fixed them:

- **Not "called from a SIBLING".** `draw` called DIRECTLY from the method fails
  the same way. The sibling was incidental.
- **Not the capture.** `print(self.n)` inside the same nested def prints `7`.
  The capture list is right too (`PXXDBG=n.caps` → `C.run.draw caps=self`).
- **It IS the RETURN TYPE.** An explicit `-> int` makes every failing case
  correct, which is what identifies it.

So the real statement is: **a nested def in a method whose return expression
reads `self.<field>` infers the wrong result type**, and it is silent.

### Cause

`PyInferExprType`'s receiver-class branch — the one that knows `self` means
`CurSelfClass` — requires the pattern `ident . ident (`. It only ever handled a
**method call**. A plain FIELD read has no `(`, so it fell straight through and
the expression took its type from the RECEIVER: the def was typed as returning a
CLASS, the caller read the field slot as an object pointer, and `print` produced
an empty line. Both an int field and a str field failed, which is what ruled out
"typed as a string" early.

Fixed by walking the whole `.field.field…` **chain** from the receiver's class,
plus a trailing `.method(...)` closing it — so `self.n`, `self.inner.k` and
`self.inner.twice()` all resolve, and `self.get()` keeps working exactly as
before.

### A false lead, recorded because it looked certain

`CurSelfClass` is restored by the method epilogue **before** the nested-def
drain runs, so a deferred body genuinely does see the wrong class — the same
shape as the lambda-prefix bug fixed an hour earlier. That was implemented
(carrying `CurSelfClass` per queue entry, in all three drains) and **changed
nothing**, because the field read never consulted `CurSelfClass` in the first
place. The carry is kept: it is correct, it is symmetric with `PyPendNestPfx`,
and the next thing that does consult `CurSelfClass` from a deferred body would
otherwise hit it.

### One case was a REGRESSION of mine, now fixed

`x = self.n; return v + x` printed 17 on `pinned` and an empty line at HEAD.
That was `86b0fc2b7`'s expression chase (`PyRetNameType`) trusting
`PyInferExprType` on `self.n` — the same wrong answer, reached through a new
path. Fixing the field read fixes it; it is pinned as a row in the test.

### Found while writing the test

Two methods of one class cannot both declare a nested def of the same name —
every method here wanted to call its nested def `draw`. Loud (a compile error),
pre-existing, and filed as
[[bug-nilpy-same-named-nested-defs-in-two-methods-collide]]; the test uses one
name per method and says why.

### Verified

`test/test_nilpy_nested_def_self_field.npy`, wired into `make test-nilpy`: nine
shapes — direct, bare `return self.n`, via a local, via a sibling def, via a
lambda, a str field, a method call, a chained field, and a chained method — all
diffed against CPython, identical. `tools/gate.sh quick` GREEN, self-host
byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
