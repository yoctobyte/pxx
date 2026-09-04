---
track: P
prio: 55
type: compat
status: done
found: 2026-08-29
found-by: claude-N
owner: frankB
---

# `type T = type byte;` — the distinct-type declaration is not parsed

```pascal
type TMyB = type byte;
var x: TMyB; c: cardinal;
begin c := $12345678; x := 5; WriteLn(x, ' ', TMyB(c)); end.
```

FPC: `5 120`. pxx: `error: unknown type: type` at the declaration.

`type T = type Base` declares a type that is layout-identical to `Base` but
DISTINCT from it for overload resolution, RTTI identity and `var`-parameter
matching — the standard Pascal idiom for a strong typedef. Plain
`type T = Base` (an alias) parses fine; only the `= type` form does not.

Loud, so ranked low per CLAUDE.md's compat table ("FPC accepts a form we
reject" → compat, ranked by how much real code uses it). It is common in FPC
RTL headers and in Delphi-lineage code, so it will recur.

Found beside [[bug-p-a-cast-through-an-ordinal-type-alias-does-not-truncate]]
while reducing rung 3 of [[feature-pascal-corpus-oop]] — deliberately filed
apart, because that one is a silent wrong value and this one is a parse error,
and folding a loud gap into a silent bug is how the silent half gets lost.

## Gate

The program above matching FPC, plus a check that the distinct type is actually
distinct where that is observable (a `var` parameter of `Base` must not accept a
`T`, once overload/parameter matching is in scope).

## Re-ranked 25 → 55 (owner, 2026-09-04)

The owner named this ticket unprompted as one he considers relevant, with the
reason the compat table asks for — **"sometimes programmers have reasons to
re-type"**. That is the "how much real code uses it" input, supplied by the one
person entitled to supply it, so the rank moves.

Not to 70: it stays below its silent sibling
[[bug-p-a-cast-through-an-ordinal-type-alias-does-not-truncate]] (prio 70, now
`done/`), because that one returned a wrong VALUE and this one refuses to
compile. Loud beats silent. But 25 was too low for a form that stops a program
building outright.

Premise re-verified before re-ranking, on `stable_linux_amd64/default/pinned`
(v403), not HEAD:
```
pascal26:1: error: unknown type: type
  near: type TMyB = >>> type byte ;
```
fpc on the same source prints `5 120`. So the ticket's report is still exactly
true a week on: it is a PARSE gap, not a silent alias. Recording that because
the two are easy to conflate — the silent-alias behaviour people remember
belonged to the sibling, and that half is already fixed.

## PARSED 2026-09-04 (frankB) — and the distinctness half is a separate ticket

`compiler/pasparser_decl.inc`, in `ParseTypeSection` right after `Expect(tkEq)`:
the `type` keyword is consumed ahead of the whole type-binding chain, so every
right-hand shape takes the arm it would have taken without it and no arm below
learns a new case. `type helper for T` is the other meaning of `tkType` in
exactly this position and is excluded by name.

`test/test_distinct_type_decl.pas` covers one RHS arm each — a builtin scalar, a
distinct type OF a distinct type, a pointer alias, an array type, a managed
string, a record, a procedural type — plus the ticket's own repro. Every row
matches fpc 3.2.2 exactly; the pin refuses the file at line 27.

**THE CONTROL COULD NOT LIVE IN THAT FILE, which is worth recording:** the guard
is written by name (`not ... 'helper'`) rather than as "skip a tkType here", and
the failure it prevents is that every `type helper` stops resolving — invisible
to all seven rows above. FPC 3.2.2 has **no `type helper` at all** (only
`record`/`class helper`; it answers `Identifier not found "helper"` in both
objfpc and delphi modes), so a control row for it cannot sit in an FPC-oracled
file. `test_type_helper_property`, `test_type_helper_typename_receiver` and
`test_class_helper_for_a_class` are that control, all three already wired, all
three run green after this change.

**The second half of this ticket's gate is NOT met and is now its own ticket.**
The gate asked for "a check that the distinct type is actually distinct where
that is observable". It is observable — measured, FPC prints `base` then
`distinct` for a two-overload probe — and pxx does not: it warns `duplicate
definition of 'P' with the same parameter types` and binds both calls to one
body. That is not fallout from this fix; it is what pxx **already** does for a
plain `type TMyB = byte`, so this spelling reached an existing loud behaviour
rather than adding a silent one. Split out as
[[bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct]] because the
missing piece is a CHANNEL, not a predicate: there is no `LastTypeAlias`, no
`Syms[].AliasIdx` and no `ProcParam` alias carrier beside `ProcParamRecId` and
`ProcParamSetEnumId`, so an alias has no identity anywhere downstream of its
declaration. Filing rather than folding, for the reason this ticket's own author
gave about its silent sibling: a loud gap and a wrong-binding gap are different
work and one hides the other.

Measured while here and NOT a defect: `SizeOf(TRec)` for
`record a, b: Integer` answers 8 in pxx and **4** in fpc's DEFAULT mode, because
FPC's default-mode `Integer` is 2 bytes. Under `{$MODE OBJFPC}` both answer 8.
The test carries the directive for that reason.

## Gate

`make compiler/pascal26` converged; `tools/gate.sh quick` GREEN with the FPC seed
canary CONCURRENT.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
