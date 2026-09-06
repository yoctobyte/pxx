---
slug: bug-p-an-unspecialized-generic-name-used-as-a-type-is-accepted-and-sized-as-nothing
track: P
prio: 35
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankS
blocked-by: []
title: "A bare generic name used as a type (`^TTest` for `generic TTest<T>`) is accepted, sized as 4, and its fields are writable"
summary: "`PBig = ^TBig` where TBig is `generic TBig<T>` compiles clean OUTSIDE the generic's own scope. It is not merely accepted: SizeOf through it answers 4 for a record whose real specialization is 32, `New(p)` allocates those 4 bytes, `p^.a := 1.0` is ACCEPTED and writes 8 bytes into a 4-byte block, and reading the field straight back gives 0. So one construct produces a heap overflow AND a wrong value AND no diagnostic. The 4 is `TypeStorageSize(tyUnknown)` — nothing was recorded — which is exactly the collision CLAUDE.md warns about: an Integer-shaped probe cannot tell a right answer from a blank one, and only a 32-byte pointee separates them. SEVERITY IS CAPPED BY REACHABILITY, deliberately: fpc REJECTS this source, so no FPC-valid program reaches it and this can only be arrived at from code that is already wrong — the claim is that the mistake gets no diagnostic, not that working code breaks. THE FIX IS NOT A BLANKET REFUSAL: inside a generic's own body the bare name legally means the current instantiation, so every generic method depends on it being accepted there; the refusal has to be scoped to uses outside the declaring generic."
---

# Measured 2026-09-06, compiler `e4abd7e3c3e7` (commit a952d4591)

```pascal
generic TBig<T> = record a, b, c: Double; t: T; end;
PBig     = ^TBig;                       { fpc: rejected. pxx: accepted }
TRealBig = specialize TBig<Double>;
PRealBig = ^TRealBig;

SizeOf(p^)  { PBig }      = 4      <- TypeStorageSize(tyUnknown): nothing recorded
SizeOf(q^)  { PRealBig }  = 32     <- the real answer

New(p);          { survives — allocates 4 }
p^.a := 1.0;     { ACCEPTED — writes 8 bytes into a 4-byte block }
writeln(p^.a);   { 0 — the write and the read do not even agree }
```

The first probe used `T = Integer`, where the true pointee size is **8** and the
blank answer is **4** — close enough to read as "a size, just wrong". Re-cut at
32 bytes on purpose, per the CLAUDE.md rule that a probe whose right answer can
collide with a type default is a guard that cannot fail.

## Scope of any fix — read this before refusing anything

Inside a generic's own body the bare name is LEGAL and means the current
instantiation; `procedure TList.Add` and an internal `PItem = ^TItem` both rely
on it. A refusal keyed on "the name denotes a generic" therefore breaks every
generic method in the tree. The condition wanted is narrower: the name is used
as a type *outside* the scope of the generic that declares it, with no argument
list. That is why this is ranked rather than fixed on sight.

## Corpus

Three fpc-testsuite `{%FAIL}` rows are this one defect and are consolidated onto
it: `tgeneric83.pp` (`{$mode delphi}`, `Test: ^TTest = Nil`), `tgeneric84.pp`
(`PTest = ^TTest`), `tgeneric85.pp` (objfpc `const Test: ^TTest = Nil`). Their
previous reason read *"invalid generic record body accepted (pre-specialization
checking)"*, which names the wrong thing — the record bodies are fine and
nothing about pre-specialization checking is involved; it is the bare name in
type position.

NOT the same as `tgeneric21.pp` (a generic nested in a generic — fpc rejects,
pxx accepts, and that one is a genuine dialect pass) or `tclass13c.pp`
(`TRootClass.Integer` — a qualified member lookup falling through to global
scope, a different missed diagnostic).

# Fixed 2026-09-06 — and the root cause was one level up from the generic

The generic name is a SPECIAL CASE of a defect with no generics in it at all:

```pascal
type PNever = ^TNeverDeclared;   { no such type anywhere in the program }
var  p: PNever;
begin p := nil; writeln(SizeOf(p^)); end.   { pxx: compiled, ran, printed 4 }
```

fpc 3.2.2: `Forward type not resolved "TNeverDeclared"`. The 4 is the same
`TypeStorageSize(tyUnknown)` this ticket measured for `^TTest` — same blank, same
collision with `sizeof(Integer)`, arrived at without a template in sight.

`ParseTypeKindInner`'s `PtrElemDepth > 0` arm tolerates an unknown pointee name,
and it must: `PNode = ^TNode;` above `TNode` is how every linked node in Pascal
is spelled. What it did NOT do was ever come back and ask. **Tolerated and
accepted had become the same thing** — there was no pending list, so a name that
never arrived was indistinguishable from one that arrived on the next line.

The fix is that list: `PendPtr*` (defs.inc), `RecordPendingPtrTarget` at the
hatch, `DrainPendingPtrTargets` after the program's final `end.` — beside the
goto-label check, which is the same shape of question.

## FIRST ATTEMPT WAS REVERTED, AND THE REASON IS THE PART TO KEEP

`393fe0184` drained ONCE, at the program's final `end.`, and was reverted three
hours later (`d11b8a1a9`) after it broke `uses syncobjs` for the whole fleet:
`palsync.pas:26` is `PMutex = ^TMutex;` with `TMutex = record` four lines below
it, the most ordinary forward pointer there is.

**Draining at the program's end asks the name question FROM THE PROGRAM SCOPE,
and a type declared in a unit reached only TRANSITIVELY is not visible there.**
Minimal repro, three files:

```pascal
unit udeep;  type PX = ^TX;  TX = record v: Integer; end;
unit umid;   uses udeep;              { and nothing else }
program pdirect; uses udeep;   -> compiles
program pdeep;   uses umid;    -> refused, on identical declarations
```

The commit argued its drain point at length and the argument was about ORDER — a
forward `^T` resolved by a LATER type section must keep working, which is true
and is still why the drain is not at the end of the type section. **Choosing a
drain point chooses the SCOPE the lookup runs in as well as the moment, and only
one of the two axes was reasoned about.** A well-argued choice on one axis reads
as a considered choice, which is what stopped anybody asking about the other.

Fixed by draining PER COMPILATION UNIT: `ParseUnit` takes a mark on entry and
drains down to it at its own `end.`, so nested `uses` (that procedure recurses)
each answer in their own scope; `ParseProgram` drains from 0 for what is left.

### The population was hand-built, and that was the actual mistake

The accept-side population in this ticket — enums, subranges, scalar aliases —
was enumerated carefully from probes written inside the one file being edited.
**A hand-built population is drawn from what its author can imagine; `lib/rtl` is
not imaginable, it is enumerable.** Sweeping all 110 lib/rtl units as
`program p; uses <u>; begin end.` takes ~13s and is now part of verifying this:

| | units | fail |
| --- | ---: | ---: |
| corrected fix | 110 | 0 |
| per-unit drain removed, everything else kept | 110 | **4** |

and the four are `syncobjs`, `atexit`, `palparallel`, `palpthread` — so **three
units nobody reported were broken too**; `make test` merely stopped at the first.

Neither gate could see it and the reason is structural, not an oversight:
`gate.sh quick`'s `pinned_rtl_canary` runs that same sweep with the PIN and
retries with HEAD only for units the PIN failed, so a unit the pin compiles and
HEAD breaks is never handed to HEAD at all. The curated 550 has no row that uses
`syncobjs`. Both were green. (frank-coordinator located the `if`.)

### And the diagnostic named a line without a file

`pascal26:26` was `palsync.pas:26` and was read against `syncobjs.pas:26`, which
is inside a comment block. **A parked diagnostic carrying a line but not a FILE
points at a real line in the WRONG file, which is worse than pointing nowhere.**
`ErrorAt` (no `near:` window) is still right — the parser stands on a closing
`end.` when this fires — so the fix is the filename, which now comes from
`PasSrcOfTok` on the token index parked beside the name. NOT the same defect as
the prescan desync that produces a `near:` window disagreeing with its own line
number; frankD put the two side by side and the discriminator is whether a window
is printed at all.

## Why the scope warning above did not turn into scoping code

This ticket said the refusal "has to be scoped to uses outside the declaring
generic", and it does — but `TemplateSrcKeyOfTok` was not needed to do it.
Measured: `SpecializeTemplate` REWRITES the template's own name inside its body
to the specialization's name before that body is ever parsed (the
`CaseEqual(s, SpecializeTemplateName)` arm in pasparser_generic.inc), so
`generic TNode<T> = record next: ^TNode; end` reaches the hatch reading
`TNode$LongInt` and resolves. The inside/outside distinction was already made,
one layer down, by machinery that exists for another reason. **The scoping the
ticket asked for was real and the mechanism it assumed would be needed was not.**

## What the drain asks, and the three rows that decide it

"Is this name a type now?", not "was this row repaired?". The difference is not
cosmetic: `ResolvePendingPointerAliases` repairs classes, records, named arrays
and pointer/record aliases, and repairs NOTHING for a forward `^T` to an ENUM, a
SUBRANGE or a plain scalar alias — those three are legal, compile, run, and
agree with fpc today, and were never broken, so no pass ever touched them. A
drain keyed on repair refuses all three. They are rows 3, 4 and 5 of
`test_forward_pointer_targets_that_resolve_late.pas` for exactly that reason.

## Deliberately still accepted

- `type PRec = ^TRec;` in one type section with `TRec` in the NEXT one. fpc
  rejects it (`Forward type not resolved`); pxx compiles it and prints the right
  answer. Accepting what fpc rejects is not a defect, and it is why the drain
  runs at the end of the PARSE rather than at the end of the type section.
- `var p: ^TRec` / `const P: ^TRec = nil` above `TRec`. Same reasoning; fpc says
  `Identifier not found`.
- A bad pointee inside a generic that is NEVER specialized: that body is never
  parsed, so nothing reaches the hatch. fpc diagnoses it; we do not. That is the
  template model, not this list.

## Corpus

`tgeneric83.pp`, `tgeneric84.pp`, `tgeneric85.pp` all refuse now and are BURNED
from `pxx.skip`. Curated 550: 386/0/114 before, and the run with the fix and the
rows still skipped was also 386/0/114 — identical to the pre-fix baseline, which
is the number that says the new refusal cost nothing *inside that corpus*. It is
not the number that mattered: the corpus has no row that uses `syncobjs`, and the
lib/rtl sweep above is what actually bounds this change.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 393fe0184.
