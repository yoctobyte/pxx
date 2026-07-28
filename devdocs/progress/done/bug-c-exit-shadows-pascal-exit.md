---
track: A
prio: 70
type: bug
---

# crtl's C `exit()` shadows Pascal's `Exit` — order-dependent

Two imports, and only one order works:

```python
from reportlab.pdfbase.pdfmetrics import stringWidth   # pulls a C unit
import tkinter as tk                                   # a Pascal unit
```
```
error: undefined variable (exit)
  near: begin TkiIntStr  0  exit >>>  end
```

The reported line is inside `lib/pcl/tkinter.pas` — its own `exit;`, an
ordinary Pascal early return. Swap the two imports and it compiles.

## Cause

A pulled C unit auto-pulls crtl, whose `<stdlib.h>` declares `void exit(int)`.
Pascal's `Exit` is not a token (`tkExit` is used only by the NilPy/C/Rust/Zig
lexers, never the Pascal one) — it resolves by NAME. Once the C `exit` is
registered, a bare `exit;` in Pascal code binds to a proc that wants an
argument.

Same family as [[bug-nilpy-import-lost-after-a-fallback-import-block]], where
crtl's `atexit` swallowed the Python module of that name. The C library
namespace is flat and shares spellings with both languages pxx compiles.

## Fix direction

A Pascal bare `Exit` must not bind to a C-imported proc. Either resolve `Exit`
before the general proc lookup in the Pascal statement path (it is a
compiler-known early return, not a library routine), or exclude procs whose
`ProcUnitIdx` is a C unit from a Pascal bare-name statement lookup. The second
is the general rule and would cover the next collision (`abs`, `system`,
`write`, `read` are all in crtl too).

## Why it matters now

It blocks songformatter's `render_backend.py`, which imports the reportlab
shims (C-backed) before tkinter — and any Pascal library pulled after a C unit
is exposed to the same shadowing.

## Gate

`make test` + a test that pulls a C unit and then a Pascal unit using `Exit`,
in that order.

> Instance of [[decide-unit-local-names-leak-to-global-scope]] — unit-local
> names are visible program-wide, so the first registration wins and the answer
> depends on import order. Fixed here at the call site; the root is that ticket.

## Log
- 2026-07-28 — resolved, commit 7f851b83c.

## Resolution

Fixed by 7f851b83c, which landed exactly the second option this ticket
proposed: the `Halt`/`Exit` soft-keyword arm in `parser.inc` now also takes the
statement path when a proc of that name EXISTS but could not be called bare
(no parenthesised argument list follows and the proc takes parameters), so
crtl's `void exit(int)` no longer captures a Pascal `exit;`. A user's own
parameterless `procedure Exit` still shadows, as before. The ticket was left in
`backlog/` by that commit.

Re-verified 2026-07-28: a program pulling a C unit (which auto-declares
`exit`) ahead of a Pascal unit containing a bare `exit;` compiles.
