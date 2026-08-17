---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from .sub import NAME` — an intra-package relative import — fails with `error: undefined variable (from)`. Plain `from pkg import NAME` parses fine; the leading dot is what breaks. This blocks ALL FOUR Python corpora (webencodings, tinycss2, html5lib, reportlab), because every real package uses relative imports in its __init__.py."
---

# A relative import (`from .sub import X`) is not parsed

- **Type:** bug (NilPy frontend, import parsing) — **Track N**.
- **Found:** 2026-08-17, first contact with a third-party corpus while working
  [[feature-nilpy-thirdparty-libraries-as-targets]]. `webencodings/__init__.py:19`
  is `from .labels import LABELS` and the compile stops there.

## Repro — five lines, no third-party code

```
pkg/sub.py        VALUE = 7
pkg/__init__.py   from .sub import VALUE
main.npy          from pkg import VALUE
                  print(VALUE)
```

```sh
python3 main.npy                      # 7
./compiler/pascal26 main.npy m        # pascal26:1: error: undefined variable (from)
                                      #   near: end  end   from >>>  sub
```

Plain `from pkg import VALUE` parses. The **leading dot** is what is not
handled — the parser appears to fall out of import handling and try to evaluate
`from` as an expression, which is why the message names `from` as an undefined
variable rather than mentioning imports at all.

## Why this is the first rung, ahead of wiring any Makefile target

An intra-package relative import in `__init__.py` is how essentially every real
Python distribution is laid out. **All four fetched corpora hit it**, so a
corpus target wired today would only assert this same parse error. Nothing
further about NilPy's third-party readiness can be measured until it works.

## Module resolution itself is NOT the problem — record this before re-deriving it

The obvious first guess (and mine) was that pxx could not find the package at
all. It can:

```sh
./compiler/pascal26 -Fu/abs/path/to/library_candidates/webencodings drv.npy drv
```

resolves `from webencodings import ...` and **begins compiling the package's
`__init__.py`**. `sys.path.insert(...)` does nothing, correctly — that is a
runtime mechanism and pxx resolves imports at compile time. Note `-Fu` is absent
from the compiler's usage line, which is what makes this easy to miss.

## Scope notes for whoever fixes it

- CPython spells several forms: `from . import name`, `from .mod import name`,
  `from ..pkg import name` (parent), and `import .mod` is NOT valid Python — so
  only the `from`-forms need to parse.
- The dot count is a *level*, resolved against the importing module's own
  package directory. Since resolution already works through `-Fu`, the likely
  shape is to translate a level-N relative name to the absolute one before
  handing it to the existing resolver, rather than teaching the resolver
  anything new.
- Check the sibling form `from . import lookup` too — `webencodings/tests.py`
  uses exactly that, so it is needed for the corpus's own test suite even after
  `__init__.py` compiles.

Likely `compiler/pyparser.inc` (import handling), which is Track N's file — but
**check before assuming**: if the resolver end lives in `parser.inc` that half
is Track A and must be filed, not edited.

## Gate

`make compiler/pascal26` + the five-line repro above answering `7`, plus
`from . import X` and a two-level `from ..pkg import X`, then
`tools/gate.sh quick` **before committing** so the FPC seed canary runs.
Stretch check that actually matters: `webencodings/__init__.py` compiles past
line 19.

---

## CORRECTION 2026-08-17, same session — the mechanism, and it is NOT "unimplemented"

Read the code after filing the above. `PyEatRelativeImportDots` already exists
(`pyparser.inc`, called from the import loop at :31679), so relative imports are
partly built. The ticket's "is not parsed" framing is too coarse. Three distinct
states, measured:

| form | result | |
| --- | --- | --- |
| `from . import sub` then `sub.VALUE` | **parses**, then `error: undefined variable (sub)` | binds nothing usable |
| `from .sub import VALUE` | `error: undefined variable (from)` | never handled |
| `from pkg import VALUE` | works | the absolute form is fine |

### The dot-eater succeeds only for the bare-dot form

```pascal
function PyEatRelativeImportDots: Boolean;
begin
  Result := False;
  if CurTok.Kind <> tkDot then Exit;
  while CurTok.Kind = tkDot do Next;
  Result := CurTok.Kind = tkUses;     { i.e. only `from . import x` }
end;
```

It returns True **only** when the token after the dots is `import`. For
`from .sub import VALUE` the next token is the identifier `sub`, so it returns
False — **after having already consumed the dots**. That side-effect-on-failure
is a defect in its own right: the caller's fallback path resumes mid-statement
with the dots gone and no way to know a relative import was intended, which is
why the error surfaces as `undefined variable (from)` and names neither the dot
nor the import.

So there are two things to fix and they are independent:

1. **`from .mod import NAME`** — the common form, unhandled. The dot-eater needs
   to report the LEVEL (dot count) and let the caller consume a module name
   after it, rather than returning a bare Boolean that conflates "no dots" with
   "dots but not the bare form".
2. **`from . import sub`** — parses but does not bind `sub` as a usable module
   name. `ParseUsesUnit` is called for it, so the unit is pulled in; what is
   missing is the local binding, and that is a different half from the parse.

Both are needed: `webencodings/__init__.py` uses form 1 (`from .labels import
LABELS`) and `webencodings/tests.py` uses form 2 (`from . import lookup, ...`).

### Where this stopped

Banked here rather than fixed — locating the second half (why `sub` is unbound)
is investigation, and this session has not been cleared. Form 1's parse looks
like a contained change in `pyparser.inc` (Track N's file); form 2 may reach the
resolver, so **check whether it lands in `parser.inc` before editing** — that
half would be Track A and filed, not fixed.

---

## ROOT CAUSE FOUND 2026-08-17 — the PRESCAN never sees a dotted import

`PyPreScanImports` (`pyparser.inc`) decides what is an import by looking one
token past `from`:

```pascal
((Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'from') and
 (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkIdent))
```

**`tkIdent` only.** For `from .labels import LABELS` the next token is `tkDot`,
so the line is invisible to the prescan, is never handed to `PyParseImportRun`,
and the statement parser later meets a bare `from` and reports
`undefined variable (from)`. That is the whole first-form failure, and it
explains why the message names neither the dot nor the import.

### And flipping that condition alone is NOT the fix — measured

Widening it to `[tkIdent, tkDot]` **regresses form 2**: `from . import sub` goes
from failing at line 2 (`undefined variable (sub)`) to failing at line 1
(`undefined variable (from)`, with the dot already consumed). Reverted, baseline
confirmed restored on both forms.

Why: there are **two** import handlers — `PyParseOneImport` (:31583) and
`PyParseImportRun` (:31688), each with its own `from` handling. Today the
prescan skips dotted lines, so form 2 reaches `PyParseOneImport`, which copes.
Widening the prescan reroutes it to `PyParseImportRun`, whose relative-import
path does not. **So `PyParseImportRun` has to handle the relative forms before
the prescan may be widened** — that ordering is the finding, and doing it the
other way round is a regression.

Two handlers for one concept is the `normalise-dont-special-case.md` smell, and
it is the reason this looks like two bugs.

## LANDED 2026-08-17: the safety half (behaviour-neutral)

`PyEatRelativeImportDots: Boolean` → **`PyRelativeImportLevel: Integer`**,
returning the dot count. The Boolean answered "is this the bare
`from . import x` form" while both callers asked "was this a relative import?" —
different questions, and on the mismatch it returned False **after consuming the
dots**, leaving the caller mid-statement with no way to know what was intended.

A lookahead that consumes on its failing path is a landmine independent of this
feature: it will misdiagnose the next bug too. The level collapses the
conflation at the source (0 = not relative, N = N dots) instead of adding a
second flag beside it, and makes `from ..pkg import X` reachable later for free.

Verified **behaviour-neutral**: both forms fail exactly as before, `gate.sh
quick` GREEN with the FPC seed canary PASS.

## What is left

1. Teach `PyParseImportRun` the relative forms (level > 0 with an identifier
   after the dots → resolve the module and fall through to the ordinary
   from-import path, which already binds names via `ParseUsesUnit` and flat unit
   scope — `from sub import VALUE` inside a package `__init__.py` works today,
   measured).
2. **Then** widen the prescan to `[tkIdent, tkDot]`.
3. Make `from . import sub` bind `sub` usably (it parses and pulls the unit;
   the local binding is what is missing).

Both handlers live in `pyparser.inc` — **Track N's file, no Track A handoff
needed**, which was an open question and is now answered.
