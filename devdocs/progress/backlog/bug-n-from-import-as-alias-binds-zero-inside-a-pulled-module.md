---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from mod import NAME as ALIAS` binds ALIAS to 0 — silently, no diagnostic — when the statement is inside a pulled `.py` MODULE. The identical statement in a top-level `.npy` program binds correctly, so it is the module path only. Silent-wrong-value class."
---

# `from mod import NAME as ALIAS` binds 0 inside a pulled `.py` module

- **Type:** bug (NilPy frontend, import aliasing) — **Track N**.
- **Found:** 2026-08-17 while verifying
  [[bug-n-relative-import-from-a-package-is-not-parsed]]. Not a relative-import
  defect: it reproduces in the absolute spelling too, and it predates that fix.
- **Class: silent wrong value.** Nothing is reported. A sum came out 5 where
  CPython said 6, and one term was quietly zero.

## Repro

```
pkg/two.py        A = 1
pkg/__init__.py   from .two import A as AA
                  S = AA
main.npy          from pkg import S
                  print(S)
```

| | |
| --- | --- |
| CPython | `1` |
| pxx | `0` |

**The dot is not the variable.** Spelling `__init__.py`'s import absolutely
(`from two import A as AA`) gives `0` just the same. (CPython rejects that
spelling with `ModuleNotFoundError`, which is an unrelated and deliberate NilPy
laxity — the point is only that pxx's answer does not change.)

## The control that localises it — a top-level program is FINE

```
two.py     A = 1
main.npy   from two import A as AA
           print(AA)
```

CPython `1`, pxx `1`. So the alias machinery works; it is the **pulled-module
path** that loses it. A `.py` module's statements go through `PyParseStatement`
/ `PyParseOneImport`, while a main program's leading imports go through
`PyParseImportRun` — and `PyParseImportRun` is the handler carrying the alias
work (`PyImpAliasSym`, the class-alias registry, the `ALIAS = NAME` desugaring
at `pyparser.inc:~31795`). `PyParseOneImport` parses `as` and **discards it**:

```pascal
      if PyIsIdent('as') then
      begin
        Next;
        if CurTok.Kind = tkIdent then Next;   { name consumed, nothing bound }
      end;
```

That is the same shape as the already-fixed
`bug-nilpy-from-import-as-alias-is-discarded`, which was fixed in
`PyParseImportRun` **only** — the twin was left. Note this makes the bug
*newly reachable*: before relative imports worked in a package `__init__.py`,
far less real code went down this path.

## Why this is worth more than its file count

`from x import y as z` is ordinary in library code, and a package's
`__init__.py` is exactly where re-exports get renamed. Binding 0 instead of
raising means a compiled third-party library can produce wrong numbers with a
clean compile — the failure mode this repo's debugging playbook calls the
expensive one.

## Fix direction, not yet chosen

This is the `normalise-dont-special-case.md` case in its textbook form: two
handlers for one concept, a fix applied to one arm, the sibling left broken —
and it is the second defect traced to that split in two days. The alias code in
`PyParseImportRun` should not be copied into `PyParseOneImport`; the two should
collapse, which is already filed as
[[refactor-n-two-import-handlers-are-twins]]. **Whoever takes this should read
that ticket first and decide whether this bug is the occasion to do the
collapse** rather than growing a third copy of the alias logic.

Also check the plain-`import x as y` form on the module path while in there —
untested here.

## Gate

`make compiler/pascal26` + the repro above answering `1` in both the relative
and absolute spellings, + the top-level control still `1`, then
`tools/gate.sh quick` **before committing** so the FPC seed canary runs.
Add a regression test alongside
`test/test_nilpy_relative_import_in_package.npy`, which deliberately avoids
aliases today precisely because of this bug.

---

## ROOT CAUSE + FIXED 2026-08-17 — the binding was queued and never materialised

Not a parse defect at all, and the guess above ("`PyParseOneImport` discards
`as`") was only half the story — the prescan's `PyParseImportRun` *does* handle
the alias for a module, and queues it correctly.

**`PyFlushImportAliases` had exactly one call site: `:32821`, in the MAIN
PROGRAM path.** `ParsePyModule` never called it. So for a pulled module the
alias symbol was allocated (which is why the name resolved instead of erroring)
and its `ALIAS = NAME` assignment was never emitted into any body — leaving a
fresh variant global, which reads as 0. That is the entire bug, and it explains
the shape precisely: a *diagnostic* would have needed the symbol to be missing,
and the symbol was the one part that worked.

### The fix

`ParsePyModule` now flushes into its own body, as the module's first statement —
which is where Python binds an import. One subtlety made it more than a one-line
call, and it is the interesting part:

**the alias queue is GLOBAL, and the main program's entries are still on it.**
The program parses its leading imports (queuing aliases) and does not flush
until `:32821`, which is *after* every unit those imports pull has been
compiled. A module draining the whole queue would emit the PROGRAM's assignments
inside ITSELF — the names would bind in the wrong namespace and the program
would be left holding the symbols with none of the assignments. That is the same
"binds 0" defect, moved up one level and harder to see.

So the flush is bounded: `ParsePyModule` records `PyImpAliasCount` on entry and
`PyFlushImportAliasesFrom(seq, base)` drains only its own suffix.
`PyFlushImportAliases(seq)` remains as `…From(seq, 0)` for the program path.

### Verified

| | CPython | pxx before | pxx after |
| --- | --- | --- | --- |
| `from .two import A as AA` in `__init__.py` | 1 | **0** | 1 |
| same, absolute spelling | — | 0 | 1 |
| top-level program control | 1 | 1 | 1 |
| the four-form probe that first exposed it | 6 | **5** | 6 |

Pinned by `test/test_nilpy_relative_import_in_package.npy` (the `RENAMED` /
`through-alias` line), CPython-oracled.

### Worth carrying: an aliased name DOES re-export, and that identifies the sibling's fix

While verifying, `from pkg import AA` was measured working when `__init__.py`
wrote `from .two import A as AA` — because the alias creates a REAL symbol in
the importing unit. The un-aliased `from .two import A` creates none and leans
on flat unit scope, which is exactly why it does not re-export.

So [[bug-n-a-package-does-not-re-export-what-its-init-imports]] is not a
visibility problem to be solved by making `uses` transitive (which the user
ruled out, 2026-08-15). It is the same missing binding: `from mod import NAME`
should bind NAME in the importing module exactly as `from mod import NAME as
NAME` already does — which is also precisely CPython's semantics, since a
from-import binds a name in the importer's namespace rather than opening a
window onto the exporter's. **One mechanism serves both tickets.**
