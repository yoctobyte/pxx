---
summary: "NilPy: `\"{1}{0}\".format(a, b)` ignores the explicit indices and substitutes left-to-right — silently prints the arguments in the WRONG ORDER"
type: bug
track: N
prio: 60
---

# `str.format` ignores explicit positional indices

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from a differential sweep of the string method surface
  against CPython (self-hosted binary at `c7d64813b`).

## Measured

```python
print("{1}{0}".format("a", "b"))   # CPython: ba    pxx: ab   WRONG
print("{0}{1}".format("a", "b"))   # CPython: ab    pxx: ab   ok
print("{}{}".format("a", "b"))     # CPython: ab    pxx: ab   ok
```

Only the REORDERING case is wrong: `{}` and `{0}{1}` happen to agree with
left-to-right substitution, so the bug is invisible until an index actually
reorders. The number inside the braces is being ignored entirely rather than
used as an argument index.

## Why it matters

Silent and order-dependent. `"{1} {0}".format(first, last)` is a common way to
swap name order, and `"{0} {0}"` (repeating one argument) is the other standard
use — both produce plausible-looking output that is simply wrong, with no error.
It will most often surface as a user-visible string with two fields transposed,
which is easy to mistake for a data problem rather than a compiler bug.

## Scope to check when fixing

- `{0}` repeated: `"{0}-{0}".format("x")` → `x-x`, and it must NOT consume two
  arguments.
- Mixing automatic and explicit numbering is a **ValueError** in CPython
  (`"{}{0}".format(...)`), not a silent answer.
- Index out of range → `IndexError`.
- Named fields (`"{name}".format(name=…)`) and format specs (`"{0:>5}"`,
  `"{:.2f}"`) — check whether those parse at all today before assuming only the
  index is missing.
- `%`-formatting is a separate implementation and tested elsewhere; this ticket
  is `str.format` only.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering each bullet above — in particular a case whose expected output
DIFFERS from left-to-right substitution, since that is the only shape that can
distinguish the broken implementation from the correct one.

## 2026-08-01 — FIXED

`PyFormatApply` (`compiler/builtin/pylib.pas`) scanned a replacement field from
`{` to `}` collecting only an optional `:spec`, and walked past the FIELD
itself without keeping it — then substituted by a sequential counter. The index
was not mis-parsed; it was never read.

Rewritten to parse `{[field][:spec]}` properly:

- an all-digits field is an **explicit index** and does **not** advance the
  automatic counter, which is what makes `"{0}-{0}"` repeat one argument;
- `{}` keeps using and advancing the counter, so Python's two numbering modes
  stay independent;
- a NON-numeric field (a named one, `{name}`) needs kwargs, which this path does
  not carry — it keeps the previous sequential behaviour rather than starting to
  error, so nothing that works today stops working.

### Verified

`test/test_nilpy_str_format_indices.npy`, wired into `make test-nilpy`,
byte-identical to CPython. Confirmed RED pre-fix — `{1}{0}` gave `ab`, and both
`{0}-{0}` and `{1}-{1}` gave `x-y`.

Covers what the ticket said made it invisible (reordering and repetition) plus
the neighbours that must not move: `{}`, `{0}{1}`, a bare `{}` with a number,
alignment specs with and without an index (`[{:>5}]`, `[{1:>5}]`), literal
`{{ }}` braces, and float precision on both indices.

The assertion was checked by executing **make's own expanded recipe**
(`make -n test-nilpy | grep test_nilpy_fmtidx26 | bash -e`) rather than by
re-deriving the escaping — the lesson from
[[bug-n-static-operand-clash-diagnostic-and-guard-test-escaping]] earlier tonight.

Native: build + byte-identical self-host fixedpoint, `testmgr --tier quick`
GREEN, `make bootstrap` exit 0 (FPC seed build — pylib.pas is a compiler input).

## Log
- 2026-08-01 — resolved, commit PENDING.
