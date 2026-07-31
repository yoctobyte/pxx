---
track: N
prio: 35
type: bug
---

# A qualified UNIT-LEVEL proc call cannot omit a defaulted parameter

A defaulted `Variant` parameter works for a METHOD called from NilPy (the
omitted argument arrives as tag 0 / None), but the same signature on a
unit-level procedure, called qualified, does not:

```python
import vunit
vunit.show("x")        # Nil Python: no overload matches
```

```pascal
procedure show(const text: AnsiString; const opts: Variant = 0);
```

The overload probe for a qualified unit-level call requires every parameter to
be supplied, so a façade written as free procedures cannot offer optional
Python-shaped options — which is why `lib/pcl/tkinter.pas` exposes options on
METHODS throughout.

## Why it is filed rather than worked around

The workaround (put it on a class) is what the façade already does, so nothing
is blocked today. It is filed because the asymmetry is invisible at the call
site: the same declaration behaves differently depending on where it lives, and
the diagnostic ("no overload matches") points at the caller rather than at the
real cause.

## Already fixed — verified 2026-07-31, closing

Re-measured rather than assumed still-broken: `TryFillTrailingDefaults`
(parser.inc) already scopes its overload probe by `qUnit` and already fills
trailing defaults for a qualified unit-level call — confirmed directly with
the ticket's own repro shape (a unit exposing `procedure show(const text:
AnsiString; const opts: Variant = 0);`, called qualified with and without
the optional argument, and a two-defaulted-parameter variant) — both work
today. Landed by an earlier, unrelated commit (the `TryFillTrailingDefaults`
introduction) without this ticket being closed alongside it. Added a
regression test so a future regression here is caught rather than silently
re-opening this exact gap.

## Gate

`make test-nilpy` with a unit exposing a defaulted parameter on a free
procedure, called both with and without the optional argument.

## Log
- 2026-07-31 — resolved, commit 51c25fb5a.
