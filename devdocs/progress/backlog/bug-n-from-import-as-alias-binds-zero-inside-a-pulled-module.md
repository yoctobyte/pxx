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
