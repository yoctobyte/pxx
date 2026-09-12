---
track: N
prio: 85
type: bug
blocked-by: []
summary: "`with E as v:` does not bind `v` when __enter__ returns SELF — and that is the idiom nearly every context manager uses. TWO failure modes from one cause: if `v` is new the compile is REFUSED (`undefined variable (v)`), and if `v` already exists the program COMPILES AND KEEPS THE OLD VALUE with no diagnostic (measured: prints 1 where CPython prints 3). Blocks the lekkerzeilen closure at app.py:4237, `with platform.open_window(...) as window:`. PRE-EXISTING — identical on the PINNED compiler, so it is not a regression from the 2026-09-12 lambda/chain work; it only became visible because those cleared the walls in front of it. NARROWED, NOT SOLVED: the protocol path runs __enter__ and __exit__ correctly and the SAME code binds `v` correctly when __enter__ returns a DIFFERENT class, so the `as` handler is not simply missing. PXXDBG=a.ast shows __enter__ emitted as a DISCARDED statement, which is the `else if entNode >= 0` arm of PyParseWithTail — so `PyIsIdent('as')` was FALSE at that point, meaning the token cursor moved between PyParseBoolExpr and the `as` check. PyCallMeth1 is the only thing in between and is the first suspect, but that is a HYPOTHESIS and is not measured. Two earlier theories were REFUTED and are recorded below so nobody re-runs them."
---

# `with E as v:` does not bind v when __enter__ returns self

## The measured table

`__exit__` present throughout; `W.__enter__` returns `self`, `M.__enter__`
returns a fresh `E`.

| `__enter__` returns | `v` pre-declared | outcome |
| --- | --- | --- |
| `self` | no | **REFUSED** — `error: undefined variable (w)` |
| `self` | yes | **WRONG VALUE, SILENT** — prints `1`, CPython prints `3` |
| another class | no | correct |
| another class | yes | correct |
| *(no `__enter__` at all, only `__exit__`)* | no | REFUSED |

`with E:` with no `as` is correct in every arrangement, protocol included.

The second row is the one that matters: it compiles clean and the body reads the
name's PREVIOUS object. No diagnostic, and a plausible value.

## Pre-existing — the control

`stable_linux_amd64/default/pinned` gives the identical answer on every row, so
this predates the 2026-09-12 chain-store and lambda-float work. It surfaced only
because those moved the closure past it (3204 -> 3305 -> 4237).

## Where it is in the closure

`lekkerzeilen/app.py:4237`:

```python
with platform.open_window("lekkerzeilen — capture", *size) as window:
    app = App(window, region=region, ...)
```

`open_window` is a context manager that returns itself, which is why the target
is the failing row and not the working one. The `*size` unpack and the keyword
arguments are NOT involved — both were ruled out (see below).

## Narrowed

`PyParseWithTail` (compiler/pyparser.inc:23393) has the `as` handler in BOTH its
protocol branch and its legacy branch, and both look correct. `PXXDBG=a.ast` on
the failing program shows:

```
AN_ASSIGN  sym541 := coerce(W(3))        <- the hidden `cm` temp, correct
AN_SEQ
  AN_CALL(__enter__) arg=sym541          <- emitted as a DISCARDED STATEMENT
  AN_SEQ ... body
```

A discarded `__enter__` is the `else if entNode >= 0 then PySeqAppend(seq,
entNode)` arm — the "run it for its effect" path taken when there is NO `as`. So
`PyIsIdent('as')` returned False even though the source says `as w`.

`PyIsIdent` requires `CurTok.Kind = tkIdent` and `as` IS a tkIdent here
(`import math as m` works and uses the same predicate). So the cursor was not
sitting on `as` when the check ran. Between `PyParseBoolExpr` and the check there
is exactly one call that could move it: `PyCallMeth1(cmCi, '__enter__', ...)`.
**That is a hypothesis. It is not measured.** The next step is to print `CurTok`
either side of that call, not to patch anything.

## Two theories already refuted — do not re-run these

1. *Object Pascal's `as` cast operator is eating `as w`* — REFUTED. `AN_AS_CAST`
   is created only by `pasparser_expr.inc:11525` and by an IR coercion at
   `ir.inc:5758`; the NilPy parser never builds one. The `kind=57` node in the AST
   dump is the coercion on the `cm` assignment and is correct. This theory looked
   confirmed by that node, which is why it is written down.
2. *It is a syntactic recognition of `return self`* — REFUTED. `s = self; return s`
   fails identically, and a class with NO `__enter__` at all fails too.

Also ruled out as irrelevant: the `*size` unpack, the keyword arguments, a
module-qualified callee, parentheses around the expression, and whether the
statement is at module level or inside a function. All four fail the same way.

## What a fix must carry

A fixture row with the name PRE-DECLARED, because that is the arm that produces a
wrong value rather than an error — an `undefined variable` row alone would pass the
moment the symbol gets allocated, whether or not the assignment happens. And a row
whose `__enter__` returns `self`, since the other-class spelling already works and
would certify the bug.
