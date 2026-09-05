---
slug: bug-p-a-string-literal-binds-to-any-typed-pointer-parameter-and-segfaults
title: "A string literal binds to any typed pointer parameter, and segfaults"
track: P
prio: 60
type: bug
status: done
found: 2026-09-05
found-by: frankH
owner: frankH
blocked-by: []
summary: "`TypesCompatible` grants `tyPointer <- tyString` deliberately -- a Pascal string marshals to a `const char*`, so a C binding needs no `PChar()` cast -- but like the `tyClass` rule beside it, it sees two KINDS and cannot see the POINTEE. So `Take('Name')` against `function Take(p: PRec)` compiled with no cast written anywhere and read the literal's bytes as the record's fields; fpc 3.2.2 refuses it (`Incompatible type for arg no. 1: Got \"Constant String\", expected \"PRec\"`). Us accepting what FPC rejects is normally not a defect here and this one is, because the acceptance DESTROYS a diagnostic and hides a MISSING OVERLOAD: `lib/rtl/typinfo.pas` has no by-name `GetStrProp(Instance, PropName)` while FPC's typinfo does, so every vendored FPC consumer writes the spelling we lack, the literal lands in the `PPropInfo` slot, and the program SEGFAULTS instead of being told the overload does not exist. Fixed in `MatchParamCompatible` by mirroring the existing `tyClass` pointee narrowing: permit `tyUnknown` (the untyped-`Pointer` sentinel, which fails open on purpose) and `tyChar`/`tyWideChar` (PChar, PWideChar), refuse the rest, reading the durable `ProcParamPtrElemTk` column and not the symbol."
---

# A string literal binds to any typed pointer parameter, and segfaults

- **Type:** bug (silent wrong memory read, surfacing as SIGSEGV) — **Track P**
- **Found:** while re-measuring [[feature-embed-dwscript-rtti]], whose body
  predicted a segfault from a different cause that has since been fixed.
- **Sibling of** [[bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer]]
  and [[bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching]]
  — the same architectural gap, one kind over.

## The reduction

```pascal
type TRec = record a, b: Integer; end;
     PRec = ^TRec;
function Take(p: PRec): Integer; begin ... p^.a ... end;
begin
  writeln(Take('Name'));   { pxx: compiled. fpc: Incompatible type for arg no. 1 }
end.
```

## Why it is a defect and not merely a divergence

CLAUDE.md is explicit that *"us accepting what FPC rejects is not a defect"*,
and that rule is right for programs someone meant to write. This case is the
exception the goal file itself names — *"prefer the answer that leaves the
mistake visible"* — for two reasons that both have to hold:

1. The acceptance **destroys a diagnostic** and replaces it with a SIGSEGV,
   which is the maximally invisible answer.
2. What it hides is not a style difference but a **missing overload**. FPC's
   `typinfo` has `GetStrProp(Instance: TObject; const PropName: string)`;
   ours has only `(instance: Pointer; p: PPropInfo)`. Vendored FPC code writes
   FPC's spelling and cannot be respelled — for DWScript, not without tripping
   MPL 1.1's fork-publish obligation. So the input is not a programmer error at
   all; it is correct FPC source meeting a library gap, and the compiler turned
   "you are missing an overload" into a crash.

## The fix

`MatchParamCompatible`, mirroring the `tyClass` pointee narrowing already there
rather than adding a differently-spelled site (`normalise-dont-special-case`).
Permitted pointees are the ones a string genuinely is: `tyChar`/`tyWideChar`,
plus the `tyUnknown` sentinel, which is both the untyped `Pointer` formal and
what a registration path that never recorded a pointee leaves behind — failing
OPEN there is deliberate, for the reason `ProcParamPtrElemTk`'s own note in
`defs.inc` gives. Frozen string kinds are normalised first, since
`TypesCompatible` does that on its own way in and a `tyShortString` argument
would otherwise walk straight past the guard.

## Tests

`test_string_literal_not_a_typed_pointer_fails.pas` (negative, message
asserted) and `..._ok.pas` (positive), wired into `test-core` beside the
sibling argument-typecheck rows. **The positive half is the load-bearing one.**
A pointer-general refusal landed the same day, ate `Show('-')` and `p := 'e'`,
and was reverted — `testmgr quick` does not run those rows and the self-host
fixedpoint cannot see the shape at all, because `compiler.pas` never binds a
`Char` to a `PChar`. Char→PChar is therefore an asserted row here, not a hope.

## What this does NOT fix, and who owns it

The typinfo gap itself. `lib/rtl` still has no by-name `GetStrProp` /
`SetStrProp` / `GetOrdProp` / `SetOrdProp`, so FPC-spelled RTTI code now gets a
clean compile error where it used to crash — better, and still not working.
That is Track B and it is the real blocker under [[feature-embed-dwscript-rtti]],
recorded there rather than here.

## Not consolidated, deliberately

This is the third spelling of "a pointer formal cannot see its pointee" in one
function. Three is the count `root-cause-over-microfix` calls a design flaw, and
it is still the wrong moment: the three permit different pointee sets, so a
shared helper would take the permitted set as a parameter — sharing the `if` and
none of the thinking, which is consolidation that only moves the special cases
inside. The overhaul is worth doing when the pointee question has one answer,
and the procedural case being reverted the same day is evidence we do not have
it yet. Site list recorded here so the count is not re-derived.
