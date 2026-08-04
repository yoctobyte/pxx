---
track: N
prio: 50
type: bug
summary: "Inside a METHOD, a nested def that captures self returns nothing when called from a SIBLING nested def — `C().run()` prints an empty line where CPython prints 17. Pre-existing (identical on pinned), and needs no lambda to reproduce."
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
