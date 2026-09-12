---
track: N
prio: 85
type: bug
blocked-by: []
summary: "FIXED 2026-09-12, AND THE TITLE IS WRONG: `__enter__` returning self has NOTHING to do with it. The real rule is that `with C(...) as NAME:` broke exactly when NAME names a CLASS, case-insensitively. `is` and `as` share one arm in the SHARED PASCAL expression parser (pasparser_expr.inc) because both are Pascal type operators; `is` has carried a `not PyExprMode` guard from the start — Python's `is` is identity, not a type test — and `as` never got it. FindUClass is case-INSENSITIVE, so `as window` resolved to `class Window`, that arm ate `as window` as a CAST, and PyParseWithTail's own `as` handler never fired. Guard now hoisted over both operators so they cannot drift apart again. Cleared the lekkerzeilen closure past ALL of app.py (4237 -> __main__.py:115). Two failure modes from the one cause: a NEW target name gave `undefined variable`, an ALREADY-BOUND one COMPILED and kept the old value silently. Fixture test/test_nilpy_with_as_names_a_class.npy, PREDECL is the load-bearing row; the PIN fails it. READ THE RESOLUTION BEFORE TRUSTING THIS TICKET'S EARLIER BODY: its \"REFUTED\" list named the correct cause and refuted it from a grep scoped to the wrong file, and its headline discriminator came from a table that moved two variables at once."
status: done
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

## Resolution 2026-09-12 — the cause was in the SHARED PASCAL EXPRESSION PARSER

`is` and `as` share one arm in `pasparser_expr.inc`, because both are Pascal type
operators. The condition was:

```pascal
if (CurTok.Kind = tkIdent) and
   ((CaseEqual(CurTok.SVal, 'is') and (not PyExprMode)) or
    CaseEqual(CurTok.SVal, 'as')) and                      { <- no guard }
   (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
   (FindUClass(GetTokenStr(TokPos)) >= 0) then
```

`is` carried `not PyExprMode` from the start — Python's `is` is identity, not a
type test. **`as` never got the same guard.** `FindUClass` is case-INSENSITIVE, so
`as window` resolved to `class Window`, this arm ate `as window` as a CAST, and
`PyParseWithTail`'s own `as` handler then never fired. The guard is now hoisted
over both operators so they cannot drift apart again — the duplicated condition is
how they drifted in the first place.

The discriminator is therefore **the target name naming a class**, not anything
about the context manager:

| shape | before | after |
| --- | --- | --- |
| `class W` ... `as w` | REFUSED | correct |
| `class W` ... `as w`, `w` already bound | **compiled, old value** | correct |
| `class W` ... `as other` (any other class name) | REFUSED | correct |
| `class W` ... `as q` (no class of that name) | correct | correct |

Positive control: the PINNED compiler fails the new fixture with
`undefined variable (w)`. Pascal `is`/`as` unaffected —
`test/test_isas_open_world_b325.pas` still prints `is=TRUE / as=later /
plain is=FALSE`, which is expected since the guard is `not PyExprMode`.

## CORRECTION — this ticket's own "REFUTED" list had the answer in it

The ticket said theory 1, *Object Pascal's `as` cast operator is eating `as w`*,
was REFUTED. **It was correct, and the refutation was wrong.** I grepped
`AllocNode(AN_AS_CAST)` in `pyparser.inc` only, found nothing, and concluded "the
NilPy parser never builds one" — true, and irrelevant: the NilPy parser delegates
its comparison/arithmetic atom to the SHARED `ParseExpr` (pyparser.inc:2166 says
so in its own comment), which is the function that builds it. The `kind=57` node I
dismissed as an IR coercion *was* the `AN_AS_CAST`, and its `ival=0` was the target
class index — the class the target name had resolved to. **A grep scoped to the
wrong file answered honestly about that file and was read as an answer about the
compiler.**

Theory 2, *a syntactic recognition of `return self`*, was refuted for a bad reason
too. The four-row table it came from moved TWO VARIABLES: every "working" row used
a manager class whose name did not match its target (`M`/`w`, `E`/`w`) and every
"failing" row used `W`/`w`. So the rows differed in the return expression AND in
whether the names collided, and the return expression was the visible one. Built
as a one-variable ladder from the WORKING program, `return self` works and the
class NAME flips the outcome. Same for the "no `__enter__` at all" row — it used
`W`/`w` and failed for the name reason.

Four further hypotheses were tested and refuted cleanly along the way, all cheap,
none the cause: `PyCallMeth1` moving the cursor (the probe shows `TokPos` 63 before
and 63 after — the cursor was ALREADY off `as`, which is what redirected the search
to the expression parser), the class index being 0, `__enter__`'s return type, and
a default parameter on `__init__`.

## The probe that ended it

A temporary `WriteLn` of `CurTok.Kind`/`SVal`/`TokPos` either side of the
`__enter__` call in `PyParseWithTail`, reverted afterwards:

```
FAILING:  PROBE before: kind=79 sval=[]   TokPos=63   (79 = tkColon)
WORKING:  PROBE before: kind=1  sval=[as] TokPos=87   (1 = tkIdent)
```

Identical `TokPos` before and after the call in both runs. That one line moved the
search from "what does the `with` parser do" to "what consumed `as` before it ran",
which is where the bug was.

## Log
- 2026-09-12 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
