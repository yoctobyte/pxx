---
track: N
prio: 85
type: bug
---

# A nested def's capture set is read before it is final

Two faces, one cause.

**Face 1 — a compile error that depends on definition order.** A lambda that
calls a sibling nested def must forward that sibling's captures (transitive
capture, `PyParseLambda`; nested defs have done this for a while). It reads
`PyCapCount[callee]` at the point the lambda is parsed — but a nested def's
capture set is not complete until its own body is parsed, and bodies are
DEFERRED. When the callee's set is still empty, nothing is forwarded and the
call fails at the callee's call site:

```python
def build(self, parent):
    cv = tk.Canvas(self)
    text = "hello"

    def draw(width_px):
        cv.create_text(80, 20, text=text)     # captures cv, text, self

    def on_resize(event=None):
        self.job = cv.after(10, lambda: draw(cv.winfo_width()))
```

```
error: nested def captures text, which is not in scope at this call
```

songformatter's real version of this compiles only because the ordering happens
to favour it; the reduced form above does not.

**Face 2 — a SEGFAULT when the callback fires.** Same shape, and when the
forwarding does happen but the callee is invoked through the CALLBACK bridge
(`cv.after(...)` → Tcl → `pycall_value` → `pyboundfn_call_ptr`), the captures
that reach the body are not the ones the caller bound. Measured on
songformatter:

- fault at `decq -0x10(%rax)` — an object RELEASE — with `rax = 0x50`, i.e. the
  integer 80: the page's `marginleft`, a captured Int64, arriving in a slot the
  callee treats as a class instance.
- `-dPXX_LIBC_HEAP` makes no difference, so it is ownership/marshalling, not
  the allocator.
- The first draw (fired from the resize callback during `update_idletasks`)
  SUCCEEDS; the crash is on the second, direct call. The stack at the fault is
  Tcl's, which is why gdb's unwind names an unrelated proc.
- Capture bookkeeping at the CALL SITE is self-consistent (`caps=16 params=16`
  at all four call sites of the enclosing def), so this is not a miscount there.

## The propagation is MULTI-LEVEL, which is what makes it a fixpoint

Measured on the reduced case above. The chain is

```
build          locals: cv, text, size, left, self
  draw         captures cv, text, size, left, self
  on_resize    captures cv, self            <- does NOT mention text
    lambda     captures cv, and calls draw
```

For the lambda to call `draw` it must supply `text`/`size`/`left` — and it can
only get them from `on_resize`, which does not capture them either, because
nothing in ITS body mentions them. So `on_resize` has to capture what the lambda
it CONTAINS needs, which in turn depends on what `draw` needs. One pass in
definition order cannot settle that; it has to be iterated to a fixpoint.

(`PyQualifyNested` already walks OUT through the enclosing prefixes, so sibling
lookup is not the problem — that was checked and reverted.)

## Shape of a fix

Compute capture sets to a FIXPOINT before any body is compiled: scan every
nested def and lambda, propagate callee captures into callers until nothing
changes, and only then register the shells and compile. That removes the
order-dependence in face 1 and makes what the bridge binds match what the body
reads in face 2.

The bound-function bridge is worth a second look while there: it passes exactly
one user argument before the bound values (`pyboundfn_call_ptr`), and the
lifting path bails out (`nOwn <> 1`, `nDef + caps > 12`) to a BARE CODE ADDRESS
with no diagnostic — a shape whose captures are then never supplied at all.
Whatever the fixpoint does, that fallback should be an error rather than a
silent wrong call.

## Where it bites

[[bug-nilpy-songformatter-first-render-walls]] — the last wall. The preview
renders its text and dies here.

## Gate

`make test-nilpy` plus a `.npy` with (a) a lambda forwarding a sibling's
captures in both definition orders and (b) the same lambda invoked through
`after`, diffed against CPython.

## Log
- 2026-07-30 — resolved, commit 8cae8770b.
