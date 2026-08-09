---
track: N
prio: 35
type: feature
---

# `with A() as a, B() as b:` — only one context manager per `with`

```python
with Ctx(3) as a, Ctx(4) as b:      # error: Expected: :, but got: (Kind: 80)
    print(a.n, b.n)
```

A compile error. Single-manager `with` is fully correct — a CPython-diffed
sweep of `__enter__`/`__exit__`, the exception path and `as` binding all matched
exactly, so this comma form is the only gap in the statement.

It is pure sugar: `with A() as a, B() as b:` is defined as nesting, so the
lowering is a loop over the comma-separated managers producing nested blocks.
The `__exit__` ORDER matters and is what a test must pin — inner exits first,
and an exception in the body must still exit both, innermost first.

Common in file-handling code (`with open(a) as f, open(b) as g:`), which is why
it is filed rather than left as a curiosity.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over two and three
managers, `as`-less managers mixed with bound ones, exit ORDER, and an exception
raised in the body (both managers must exit, innermost first).

## 2026-08-09 — IMPLEMENTED

`PyParseWith` was split into `PyParseWithTail` (one manager and everything to
its right), which recurses on the comma. Nesting is not an approximation of the
comma form — Python DEFINES it that way — so `__exit__` order and the exception
path come out right by construction rather than by hand.

**The hour this cost, and it is a recorded landmine:**
`bodyNode := PyParseWithTail;` — a BARE own-function name READS `Result` in this
dialect instead of recursing. It compiled, recursed not at all, handed back an
uninitialised node, and left the remaining managers in the token stream — so the
error surfaced as `undefined variable (as)` on the NEXT manager, several tokens
away from the cause. Probes showed the comma branch firing and the recursion's
entry probe never printing, which is what named it. `PyParseWithTail()` with
parens is the fix. See `project_bare_funcname_result_partial`; the note says it
had already bitten twice, and this is the third.

**Found while verifying, filed separately:** `return` from inside a `with` does
NOT run `__exit__` — pre-existing, not specific to multiple managers, and silent
(the returned value is right; only the release is lost). The source comment at
that lowering claims try/finally covers "the exception path and break/return
too"; the exception path is genuinely correct, `return` is not, and `break` /
`continue` were never measured. Filed as
`bug-nilpy-return-inside-a-with-skips-exit`. The test deliberately does not pin
today's answer for it.

Verified against CPython: one, two and three managers; `as`-less mixed with
bound; the exception path (both exit, innermost first, exception still
propagates); hand-written nesting compared against the comma form; an
`__enter__` returning something other than self; and a loop inside a
multi-manager body. `gate.sh quick` GREEN.
