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

## Bounded collapse check (asked for, ~30 min) — NOT collapsible in this ticket

The ordering constraint below is a symptom of two handlers serving one concept,
so before working around it I checked whether they merge. **They do not, inside
this ticket's scope.** Recording the reasoning so nobody re-runs the check.

| | `PyParseOneImport` | `PyParseImportRun` |
| --- | --- | --- |
| size | 105 lines | **283 lines** |
| callers | **1** (:23635, an import inside a block) | **4** (:17820, :32012, :32778, and the prescan) |
| role (its own forward decl) | "ONE import statement, inside a block" | "`import` / `from ... import`, **wherever it appears**" |

`PyParseImportRun` is a **superset**, not a peer: the extra ~178 lines are alias
binding (`PyImpAliasSym`), consumed-only roots (itertools/collections), the
`typing` special list, and the soft/try-import handling. The tree already knows
they are duplicated — `:31581` says *"Shares the resolver with
PyParseImportRun"* and `:31890` / `:31900` call each other **"the twin list"**
and **"the twin site"** outright.

So the collapse direction is forced: `PyParseImportRun`'s loop body should *be*
`PyParseOneImport`, which means first lifting those ~178 lines into the shared
body and then re-verifying four call paths, one of which is the prescan whose
routing is exactly what is fragile here. **That is a parser refactor, not a
corpus fix**, and doing it under a ticket about compiling webencodings is how a
corpus ticket becomes an afternoon in the import parser.

Filed separately: [[refactor-n-two-import-handlers-are-twins]]. Taking the
staged route here, as agreed.

## The trap this leaves for the next person — state it in these terms

Widening the prescan to `[tkIdent, tkDot]` is a one-line change that is
**obviously correct about the prescan** and still wrong, because it silently
reroutes `from . import sub` from the handler that copes to the one that does
not. This is `normalise-dont-special-case.md`'s "fix one arm of a double case,
grep for the sibling" — except the sibling is not a second call site, it is a
second **destination**. Nothing in the diff hints at it; it is only visible by
running the *other* form after making the change.

So: **after touching import routing, run both relative forms, not the one you
were fixing.**

## Dead ends — what is ALREADY DONE and must not be re-walked

Three rebuild-and-measure cycles went into locating the prescan condition, one
of which had to be reverted. Recording what those ruled out, because a dead end
nobody wrote down gets walked again.

1. **`sys.path.insert(...)` — not a route, ever.** The obvious CPython move, and
   it silently does nothing: runtime list, compile-time resolver. Now a
   permanent-limit entry in `devdocs/dev/nilpy-semantics-divergences.md`.
   The answer is `-Fu`.
2. **"pxx cannot resolve third-party packages" — false, and it was my first
   diagnosis.** `-Fu <parent of package dir>` resolves the package and begins
   compiling its `__init__.py`. The misleading part is that without `-Fu` the
   error is `no unit named X`, a feature-missing message for a feature that
   exists ([[doc-n-fu-is-how-a-python-package-is-found]]).
3. **Teaching the two import handlers the dotted form is ALREADY IN PLACE and
   changed nothing on its own.** Landed in 22da0d833: `PyRelativeImportLevel`
   plus a fall-through at *both* call sites (`PyParseOneImport:31602`,
   `PyParseImportRun:31700`) for "level > 0 and the next token is an
   identifier". Measured after: **both relative forms fail exactly as before.**
   The reason is item 4 — those handlers are never reached for a dotted import.

   **So do not start by re-editing the call sites.** That is done. Start at the
   prescan.
4. **The prescan is the gate, and widening it alone REGRESSES the sibling.**
   `PyPreScanImports` requires `tkIdent` one token past `from`, so a dotted line
   is invisible to it. Widening to `[tkIdent, tkDot]` reroutes
   `from . import sub` from `PyParseOneImport` (copes) to `PyParseImportRun`
   (does not), moving its failure from line 2 to line 1. Measured, reverted,
   baseline confirmed restored on both forms.

### The resulting order, which is the actual finding — SUPERSEDED, see FIXED below

`PyParseImportRun` must handle the relative forms **first**; only then may the
prescan be widened; the `from . import sub` local binding is third and
independent. Any other order regresses something that works today.

Also verified while in there: `from sub import VALUE` and `import sub` **inside
a package `__init__.py` both work today** — so nested imports are fine and the
defect is specific to the leading dot. That control is what proved the dot, not
the nesting, is the variable.

---

## FIXED 2026-08-17 — there was a THIRD site with the same condition, and it was the one that mattered

Both relative forms now work end to end. The fix is two characters wider than
the previous session's, and the reason it was not found is worth more than the
fix: **the search stopped at the first site matching the pattern.**

```
CPython   pxx before   pxx after
from .sub import VALUE (inside pkg/__init__.py)   7   error: undefined variable (from)   7
from . import sub      (inside pkg/__init__.py)   7   error: undefined variable (sub)    7
```

### The third site

`PyPreScanImports` was correctly identified as requiring `tkIdent` one token
past `from`. **`PyParseStatement:23626` has the identical condition**, and *that*
is the gate a relative import in a real package actually hits:

```pascal
if (CurTok.Kind = tkUses) or (PyIsIdent('from') and (TokPos < TokCount) and
    (Tokens[TokPos].Kind = tkIdent)) then     { -> [tkIdent, tkDot] }
```

A pulled `.py` MODULE parses its statements through `PyParseStatement`
(`ParsePyModule`'s body loop), not through the main program's leading
`PyParseImportRun`. So:

| where the relative import is written | path | worked before? |
| --- | --- | --- |
| the main program (`.npy`) | `PyParseImportRun` at :32778 | **yes** — and `test_nilpy_relative_import.npy` asserted exactly this |
| a package's `__init__.py` | `PyParseStatement` gate at :23626 | **no** |

That table is the whole bug. The existing regression test covered the form that
already worked, in the position no third-party package ever uses.

### Widening BOTH sites also dissolves the recorded ordering constraint

The previous session measured that widening the prescan alone regresses
`from . import sub` from a line-2 failure to a line-1 one, and concluded that
`PyParseImportRun` must learn the relative forms first. **That conclusion was an
artefact of changing one of the two gates.** Re-measured here:

- prescan widened alone → form 1 unchanged, form 2 regressed. *Reproduced the
  recorded result exactly.*
- prescan **and** statement gate widened → **both forms work.** No handler
  change was needed; the fall-throughs landed in 22da0d833 were already correct
  and were simply never reached.

So "step 1 then step 2 then step 3" was three steps for what is one change at
two sites. The staged plan is retired, not executed.

### Verified spellings

`from .mod import NAME`, several names at once, `from . import mod` with
qualified access, and both in one `__init__.py` — all agreeing with CPython.
Pinned by **`test/test_nilpy_relative_import_in_package.npy`** (a real package
under `test/nilpy_relpkg/`), wired into `test-nilpy` in the Makefile next to its
top-level sibling. CPython is the oracle for this one and agrees, which the
older test could not manage.

### The stretch check the Gate section asked for

`webencodings/__init__.py` compiled with
`-Fu library_candidates/webencodings`: **past line 19**, now stopping at
**line 50, `codecs.CodecInfo`** — a `mimic_codecs` surface gap (Track B), not a
frontend one. The blocker this ticket was filed for is gone.

### Two SEPARATE defects found while verifying, both pre-existing and NOT dot-related

Both were caught only because the controls were run in the absolute spelling
too, and both are filed rather than fixed here:

1. **A name imported into a package's `__init__.py` is not re-exported.**
   `from pkg import VALUE` fails with `undefined variable (VALUE)` when
   `__init__.py` got VALUE via an import — relative *or absolute*, identically.
   A name `__init__.py` DEFINES re-exports fine. Flat unit scope.
   → [[bug-n-a-package-does-not-re-export-what-its-init-imports]]
2. **`from mod import NAME as ALIAS` binds 0 inside a pulled module** — silently,
   no diagnostic. The same statement in a top-level program binds correctly, so
   it is the module path only. This is the silent-wrong-value class.
   → [[bug-n-from-import-as-alias-binds-zero-inside-a-pulled-module]]

The second one is why the multi-form probe printed 5 where CPython printed 6.
Nothing announced it; it was one term off in a sum.

### Method note, since the previous session's ordering finding did not survive

The recorded regression was real and reproduced exactly. What made it point the
wrong way is that it was read as evidence about the HANDLERS when it was
evidence about a second GATE — `normalise-dont-special-case.md`'s "grep for the
sibling" applied to the routing condition rather than to the handler. The
condition `Tokens[i + 1].Kind = tkIdent` appears at three sites; grepping the
*shape* of the condition, not the name of the routine, is what finds all three.
