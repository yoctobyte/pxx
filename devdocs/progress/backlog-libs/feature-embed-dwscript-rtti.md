---
slug: feature-embed-dwscript-rtti
title: "dwsRTTIExposer -- auto-bind host classes to script via Delphi extended RTTI"
track: B
prio: 40
type: feature
status: backlog
owner: ""
blocked-by: [feature-b-delphi-extended-rtti-object-model]
summary: "SPLIT 2026-09-06 AND THIS TICKET IS NOW THE EXPOSER HALF ONLY. The core went to [[feature-embed-dwscript-core]] (corpus rung 4, startable today) and the blocker this half waits on is now a filed row, [[feature-b-delphi-extended-rtti-object-model]], instead of a sentence -- the ranker had been seeing prio 40 with blocked-by [] for work nobody could begin. PREMISE STILL FALSE AND STILL THE HEADLINE: `dwsRTTIExposer` does not use `typinfo`. It uses Delphi EXTENDED RTTI -- 15 distinct `TRtti*` classes including `TRttiIndexedProperty` eight times -- and fpc 3.2.2 CANNOT COMPILE IT EITHER (it has TRttiContext/TRttiType, not TRttiIndexedProperty), so our usual oracle settles nothing here. pxx `lib/rtl/rtti.pas` exports TRttiMethod and TRttiProc and has no TRttiContext at all. TWO CLAIMS THAT WERE HERE ARE NOW CORRECTED. (1) This summary said the ONLY remaining wall was Delphi dotted unit-scope names; that feature LANDED -- [[feature-p-resolve-delphi-dotted-unit-scope-names]] is in done/ and Source/pxxlib.cfg carries 11 unitalias rows. (2) Its replacement, recorded in that done ticket, was that the wall moves to `lclintf` and DWScripts FPC branch WANTS LAZARUS. Measured false at 8b55d1918 / compiler 5ca36ce7aae9: an EMPTY `lclintf.pas` makes the compile walk straight past it, LCLIntf is never qualified anywhere in dwsXPlatform, and what it was load-bearing for is a transitive re-export of TCriticalSection -- our own `syncobjs` has a real one. What remains is an ordinary RTL gap ladder (TFileName, TLightweightMREW, IMultiReadSingleWrite), all recorded on the core ticket. THAT CORRECTION ALSO FIXES A CITATION: the done ticket says the Lazarus problem was Recorded on [[feature-embed-dwscript-rtti]] and it never was -- the sentence read as a receipt for a write that did not happen. Corpus is 96 .pas in Source/ (128 including subdirs), not the 102 claimed here before. The typinfo work recorded below was real FPC parity, is differentially verified, serves dwsComp.pas, and moves this ticket zero lines. Nothing vendored; MPL 1.1 obligations below still apply to any demo."
---

# DWScript — compile under pxx + RTTI auto-bind (scripting stress test)

- **Type:** feature / investigation (real-world compat target + RTTI driver)
- **Track:** P (Pascal frontend) — rung of [[feature-pascal-corpus-expansion]]
- **Status:** backlog
- **Owner:** — (**Track B** drives the compile + files gaps; the RTTI half is a
  **Track A** typinfo/codegen driver. Built on `$(PXX_STABLE)`, never rebuilt.)
- **Opened:** 2026-06-26
- **Upstream:** `github.com/EricGrange/DWScript` (mirror; canonical on bitbucket
  egrange/dwscript). Object-oriented Object-Pascal scripting engine — full OOP,
  faster, JS codegen. Delphi-leaning; FPC support weaker than Pascal Script.
- **License:** **MPL 1.1**. Free in open/closed/commercial, but must credit
  DWScript in app credits **and** include/link its source; **modifications to
  DWScript's own source files must be published** (file-level copyleft). Fine to
  vendor; the fork-publish obligation matters if we patch its units.
- **Relation:** the brutal cousin of [[feature-embed-pascal-script]] (do that
  first). Sibling of [[feature-synapse-compile-check]]. The RTTI half is the real
  driver for [[feature-metaclass-descendant-enforcement]]-adjacent typinfo work —
  see "the interesting coupling" below.

## The `blocked-by` edge, and why it is on THIS ticket and not a nearer one

*Added 2026-08-28 by frankB.*
[[bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching]]
is what stops `GetPropInfo(AnObject, 'Name')` — the instance-taking spelling —
from resolving: the overloads exist in `lib/rtl/typinfo.pas` and are never
selected, so the call binds the `PClassRTTI` arm and segfaults.

The edge sits here because this is the only ranked ticket that actually needs
that spelling. **Checked rather than assumed:** every existing consumer in this
repo — `classes_lite.pas:130,155`, `gtk3widgets.pas:552,561,580,585` — calls
`GetPropInfo(cls, name)` with a class pointer it already holds, so none of them
is blocked and an edge on any of them would be false. `dwsRTTIExposer`'s whole
premise is binding an arbitrary HOST OBJECT handed in from script, which is the
instance spelling by construction, and vendored FPC code will spell it FPC's way.

A false edge would rank correctly for the wrong reason and outlive the reason —
so if the RTTI half of this ticket turns out to reach only the type-level API,
delete this edge rather than leaving it as decoration.

## CORRECTION 2026-09-05 (frankH): both halves of the block above are stale

*The section above is kept as written -- it is history, and its reasoning was
sound on the evidence it had. This is what re-measuring found.*

**The blocker is closed.** `bug-p-a-parameters-pointer-element-type-is-lost-
between-registration-and-overload-matching` is `status: done`, in `done/`. Its
fix is the pointee narrowing now at `symtab.inc` in `MatchParamCompatible`,
whose own comment names this exact call: *"a pointer-taking overload was a
VIABLE candidate for a class argument and was then preferred over the exact
class match, so typinfo's `GetPropInfo(AnObject, 'Caption')` -- the spelling
every FPC consumer uses -- bound to the PClassRTTI arm and segfaulted."*

**So the instance spelling resolves.** Measured at `c9cbcd292`, compiler
`dc2853adbdf0`, against a `TThing` with published `Name: string` and
`Count: Integer`:

```
instance spelling: bound          { GetPropInfo(t, 'Name') }
ord prop  = 42                    { GetOrdProp(t, GetPropInfo(t, 'Count')) }
str prop  = zaphod                { GetStrProp(t, p) }
done
```

No segfault, and the class spelling resolves too. **Nothing in this ticket is
blocked on overload matching any more**, and the `blocked-by:` frontmatter --
which was always `[]`, so the edge lived only in the prose above -- is correct
as it stands.

**The segfault is real and has a different cause.** The probe that found it
spelled the call the FPC way:

```pascal
GetStrProp(t, 'Name')     { segfaults }
GetStrProp(t, p)          { works, p from GetPropInfo }
```

`lib/rtl/typinfo.pas` declares exactly one `GetStrProp`, taking
`(instance: Pointer; p: PPropInfo)`. **FPC's typinfo also has the by-name
arm**, so every vendored FPC consumer -- `dwsRTTIExposer` included -- writes
the first spelling. There is no overload to bind, and instead of saying so the
compiler accepts the string literal in the `PPropInfo` slot and dereferences
it. `TypesCompatible` grants `tyPointer <- tyString` deliberately (a Pascal
string marshals to a `const char*`, so a C binding needs no `PChar()` cast) and,
exactly like the `tyClass` rule one block up, **it sees two KINDS and cannot see
the pointee.** Reduced away from RTTI entirely:

```pascal
type PRec = ^TRec;
function Take(p: PRec): Integer; ...
Take('Name')    { pxx: compiles, then reads the string's bytes as fields }
                { fpc: Incompatible type for arg no. 1: Got "Constant String" }
```

This is the third spelling of one rule in that function -- the `tyClass`
pointee narrowing, an ordinal one, and this. Not being consolidated yet, and
deliberately: the three permit different pointee sets, so a shared helper would
take the permitted set as a parameter and share the `if` and none of the
thinking. The overhaul is worth doing when the pointee question has one answer.

**Us accepting what FPC rejects is normally not a defect here** -- CLAUDE.md is
explicit. This one is, and the distinction is worth keeping straight: the
acceptance DESTROYS a diagnostic and turns it into a SIGSEGV, and it hides a
MISSING OVERLOAD rather than merely differing about a legal program. *"Prefer
the answer that leaves the mistake visible"* is the goal file's own test, and a
segfault is the maximally invisible answer.

**So the work this ticket actually needs, neither item named by the analysis
above:**
1. **Add the by-name typinfo overloads** (`GetStrProp`, `SetStrProp`,
   `GetOrdProp`, `SetOrdProp`, taking `(Instance, const PropName: string)`).
   Track B, and this is the real DWScript blocker -- vendored FPC code spells
   it this way and cannot be edited to spell it ours without breaching the
   MPL fork-publish obligation noted above.
2. **Refuse a string literal in an unrelated typed-pointer parameter.**
   Track P, filed as its own bug, fix in hand.

Neither is a reason to keep an edge on this ticket: (1) is inside its own scope
and (2) is a general compiler bug that would be wrong to hang here, for exactly
the reason the section above gives for not hanging the old one on a nearer
ticket.

**Earliest sighting of the unrelated pin seam, recorded because it is the same
kind of fact:** frankB hit `lib/rtl/typinfo.pas` refusing to compile under pin
v403 at ~18:30 the same day, with `TMethod` in the diagnostic's own `near:`
window, while trying to use the pin as a control. It recorded *"the pin is not
a control here"* and moved on -- correct for its purpose. The finding existed
in a log 90 minutes before it existed in anyone's head.

## Why this is the sharper test case

DWScript's headline feature is `dwsRTTIExposer.pas` — **expose any host class to
script automatically via extended RTTI**, no manual registration ("integrate with
anything in the hardcoded library"). That is exactly the feature worth having,
and it only works if **pxx emits walkable extended RTTI**. So this ticket couples
two things:

1. **Compile DWScript under pxx** — a much harder Object Pascal codebase than
   Pascal Script (generics, anonymous methods, advanced RTTI, Delphi-isms). As a
   conformance test it finds far more gaps — deliberately. Expect a stream of
   Track A tickets; that is the point.
2. **Make the RTTI connector actually bind** — needs `lib/rtl/typinfo.pas` + the
   compiler's RTTI emission rich enough that the exposer can enumerate published
   members of a host class and call them. This is the concrete, valuable target
   for the extended-RTTI backend (a real consumer, not a synthetic one).

## Approach

- Sequence **after** Pascal Script lands — reuse the `{$mode delphi}` / mimic-fpc
  groundwork and the gap-filing rhythm.
- Phase 1: compile the DWScript **core** (tokenizer, compiler, exec) only — skip
  the RTTI connector — and run a plain script with no host binding. Gate the long
  tail of language gaps as Track A tickets.
- Phase 2: bring up `dwsRTTIExposer` against pxx RTTI; expose one host class,
  call a method from script. This is where the typinfo/RTTI-emission work gets
  driven and validated.

## Done when

Phase 1: `$(PXX_STABLE)` builds the DWScript core and runs a script. Phase 2: a
host class is reachable from a script purely via the RTTI exposer (no manual
registration), proving pxx's extended RTTI is walkable.

## License compliance (we honour it)

If we ship a demo or test app on DWScript, we **follow MPL 1.1 and give the
attribution** — credit DWScript in the app's credits, include or link its source,
and if we patch any DWScript unit, publish those changes (file-level copyleft).
Fair trade; bake the credit + source link into the demo from the start.

## Risk / note

This is a deep target — likely the single richest source of Track A language +
RTTI tickets we have. Treat it as a long-running driver, not a quick win; park in
`unfinished/` between bursts, keep the gap tickets flowing.


---

## 2026-09-01 (frankH) — the blocker is cleared; edge removed after RUNNING it

`bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching`
is in `done/`, and the instance spelling this ticket needs now resolves —
checked by running it rather than by reading the folder, because `done/` is a
claim about the past and the repro is a claim about this binary:

```pascal
o := TFoo.Create;  o.Name := 'hello';
pi := GetPropInfo(o, 'Name');      { the INSTANCE spelling, not PClassRTTI }
writeln(pi^.NamePtr^);             { -> Name }
```

It binds the `TObject` overload and returns the right `PPropInfo`, so the
premise of the edge ("the overloads exist and are never selected, so the call
binds the `PClassRTTI` arm and segfaults") no longer holds.

**The ticket itself is NOT stale.** DWScript is not vendored anywhere in the
tree (`grep -rl dwsRTTIExposer` finds nothing), so the work is untouched, not
done. Only the edge went.

One note for whoever takes it, from the ticket's own instruction: it says to
delete this edge if the RTTI half turns out to reach only the type-level API.
That is not why it went — the instance spelling was the blocker and it works
now. If a NEW blocker appears, file it rather than reviving this slug.

## 2026-09-05 (frankH) — the by-name typinfo half is LANDED; vendoring is what is left

The CORRECTION above named two pieces of work. Both are now done, and the second
one grew a third piece that only the first two could have exposed.

**1. The by-name typinfo arms exist.** `lib/rtl/typinfo.pas` gained the sixteen
FPC spellings it was missing — `GetOrdProp` / `SetOrdProp`, `GetInt64Prop` /
`SetInt64Prop`, `GetStrProp` / `SetStrProp`, `GetFloatProp` / `SetFloatProp`,
`GetObjectProp` / `SetObjectProp`, `GetEnumProp` / `SetEnumProp`, `GetSetProp` /
`SetSetProp`, `GetMethodProp` / `SetMethodProp`, and `IsStoredProp`, each taking
`(instance: TObject; const name: string)`. Each is the existing `PPropInfo` arm
with the lookup folded in.

**Differentially verified, not self-consistently.** `test/lib_typinfo_byname.pas`
was compiled by `fpc 3.2.2 -Mdelphi -O1` against **FPC's own typinfo** and by pxx
against ours, and the ten comparable rows matched **byte for byte** — including
the set rendering in both bracket modes. The four rows that do not compare are a
name that names no published property: FPC raises `EPropertyError`, we answer the
accessor's zero. That divergence is deliberate and is stated in the unit's
interface — typinfo cannot `uses sysutils` (the `Exception`-collision that
`TiCompareText` exists to dodge), so it has no exception class to raise, and a
zero keeps a misspelled name a visible wrong value rather than an unhandled trap
inside a scripting host.

**2. A stale WARNING was retracted, which is worth more than it sounds.**
The interface carried, in capitals, *"THESE ARE NOT REACHABLE YET, AND CALLING
THEM CRASHES"* over the `TObject`-taking lookups, plus a standing instruction to
spell them `GetPropInfo(GetInstanceRTTI(Pointer(obj)), name)`. Re-measured under
**both HEAD and the PINNED stable** — the pin being the one that matters to a
Track B consumer — the instance spelling binds and answers correctly on both.
The warning was true when written and false today, and a stale imperative in a
header is obeyed long after it stops being true. Retracted in place rather than
deleted, so a reader who remembers it sees it withdrawn.

**3. THE GUARD HAD A SECOND ARM AND ONLY THE FIRST WAS CLOSED.** Exercising the
new arms found that `SetEnumProp(t, 'C', 'clGreen')` segfaulted while
`SetEnumProp(t, 'Col', 'clGreen')` worked. **A one-character string literal is
tagged `tyChar`, not `tyString`**, so the pointee narrowing landed earlier the
same day walked straight past it and the literal went into the `PPropInfo` slot
exactly as before. A guard whose verdict turned on the LENGTH of an identifier —
and one that printed nothing at all for the case it missed. Widened in
`MatchParamCompatible` to include `tyChar`/`tyWideChar`, with the
`PChar`/`PWideChar` pointee exclusion untouched, which is what keeps it clear of
the over-wide refusal `4760474da` was reverted for; `Char -> PChar` remains an
asserted row, not a hope.

## What is actually left

**Only the vendoring.** No compiler or RTL gap is known to block DWScript now,
and the two this ticket did name are closed. The next session on it should clone
DWScript outside the repo (the reversible half, as
[[feature-embed-pascal-script]] did) and drive `dwsRTTIExposer` until something
fails — per the umbrella rule, attempt the target rather than triage.

**One delivery caveat, and it is the usual one.** The by-name arms need a
compiler carrying the char-literal narrowing. **Under the current pin they still
mis-resolve and crash**, so `test/lib_typinfo_byname.pas` is gated with
`$(COMPILER)` and not `$(PXX_STABLE)`; it moves to the pinned `lib-test` set at
the next pin. A Track B consumer built against the pin cannot use these arms yet.

## 2026-09-05 (frankH), later — THE TARGET WAS ATTEMPTED, AND THE TICKET'S OWN PREMISE IS FALSE

Everything above is about `typinfo`. Per the umbrella rule — grow by attempting
the target, never by triaging — I cloned DWScript outside the repo and pointed
pxx at it. **`dwsRTTIExposer` does not use `typinfo`.**

Measured at HEAD `af8b53310`, compiler `450d7de641d8`, against
`github.com/EricGrange/DWScript` (shallow clone, scratchpad, not vendored):

- `dwsRTTIExposer.pas` (1088 lines) declares
  `uses System.Classes, System.SysUtils, System.RTTI, System.TypInfo, ...` and
  uses **15 distinct `TRtti*` classes** — `TRttiType` ×17, `TRttiMethod` ×13,
  `TRttiProperty` ×8, **`TRttiIndexedProperty` ×8**, `TRttiParameter`,
  `TRttiInstanceType`, `TRttiDynamicArrayType`, `TRttiSetType`,
  `TRttiRecordType`, `TRttiInterfaceType`, `TRttiEnumerationType`, `TRttiField`,
  `TRttiNamedObject`, `TRttiMember`, `TRttiContext`. That is Delphi's **extended
  RTTI object model**, not the classic `GetPropInfo`/`GetStrProp` API.
- Across all 102 units in `Source/`, exactly **one** file uses the classic
  typinfo accessors at all: `dwsComp.pas`.
- `Packages/` holds **only Delphi packages** (D2009, D2010, DXE…DXE7, D10Rio,
  D11, D11.1). There is no Lazarus/FPC package. `dws.inc` names FPC exactly
  **twice**, both `{$IFNDEF FPC}` — FPC is a case it excludes, not one it
  supports. The ticket body's own line 23 already said *"Delphi-leaning; FPC
  support weaker than Pascal Script"*; the summary asserted the opposite in
  stronger words, and the summary is the part everyone reads.
- **fpc 3.2.2 cannot compile `dwsRTTIExposer` either.** It has `TRttiContext` and
  `TRttiType` — a probe resolving `TObject` runs and prints `TObject` — and it
  has **no `TRttiIndexedProperty`** (`Error: Identifier not found`), which that
  unit needs eight times.
- pxx's `lib/rtl/rtti.pas` is 294 lines and exports `TRttiMethod` and
  `TRttiProc`. There is no `TRttiContext`; `TRttiContext.Create` does not parse.

**So the by-name typinfo work above was worth doing and is not what this ticket
needed.** It is real FPC parity, it is differentially verified, and `dwsComp.pas`
is one of its consumers — but it does not move `dwsRTTIExposer` one line.

### The wall the corpus actually hits, and it was a FLAG, not a gap

Both this ticket and [[feature-embed-pascal-script]] record stopping on a `{$IF}`
comparison — pxx answers `conditional directive: float literals not supported`
on `{$IF CompilerVersion>21.0}`. **That is not a compiler gap.** Those directives
sit inside `{$IFNDEF FPC}`, so a compiler that defines `FPC` never evaluates
them: `--mimic-fpc` removes the wall outright, measured on four units. The
pascal-script ticket's note that uPSRuntime *"stops earlier on a `{$IF}`
comparison"* should be re-measured with that flag before anyone treats it as a
blocker.

With `--mimic-fpc -Mdelphi`, the next and only wall is **Delphi dotted
unit-scope names**: 7 of 8 probed units stop at `unit source not found:
system.classes` / `system.sysutils`, and the eighth, `dwsStrings`, **compiles
clean**. Filed as [[feature-p-resolve-delphi-dotted-unit-scope-names]], with the
measurement that fpc 3.2.2 fails identically and that `pxxlib.cfg` — the
per-directory manifest this repo already has — is the right home for the alias
table.

### What this ticket should become

Not a recommendation I can make alone, so both readings are stated:

1. **The DWScript CORE** (compiler, symbols, runtime — 100 of the 102 units) is a
   legitimate corpus target and is blocked on exactly one nameable feature, now
   filed. That half is alive and is worth its prio.
2. **`dwsRTTIExposer` specifically is not reachable** and will not be until pxx
   has Delphi extended RTTI, which is a large feature our own oracle only partly
   has. A ticket whose TITLE is the RTTI exposer is ranked for work nobody can
   start.

The honest move is to split them rather than to demote or reject the whole: the
core is a good target, the exposer is a different and much larger one. Left for
whoever picks this up, because choosing between "one ticket re-scoped" and "two
tickets" is a judgement about the backlog's shape rather than a measurement.

## 2026-09-06 (frankH) — THE SPLIT THIS TICKET ASKED FOR, AND WHY IT IS TWO TICKETS

The section above left the choice between "one ticket re-scoped" and "two
tickets" to whoever picked this up, calling it a judgement about the backlog's
shape rather than a measurement. **It turned out to be a measurement**, and the
measurement pointed one way.

### First, the staleness check, because both walls on record were wrong

**Wall 1 is gone.** [[feature-p-resolve-delphi-dotted-unit-scope-names]] landed
and is in `done/`. `Source/pxxlib.cfg` already carries its 11 `unitalias` rows.

**Wall 2 never existed.** That done ticket recorded the replacement: all eight
probed units now stop at `lclintf`, and *"telling DWScript we are FPC sends it
into Lazarus"*. Measured at `8b55d1918`, compiler `5ca36ce7aae9`:

| stub dropped into `Source/` | wall |
| --- | --- |
| none | `unit source not found: lclintf` (`dwsxplatform.pas:76`) |
| **an EMPTY `lclintf.pas`** | `base type not found: TCriticalSection` (`:99`) |
| `lclintf` re-exporting our `syncobjs` | `TLightweightMREW` (`:141`), `TFileName` (`:163`) |

An empty unit satisfied it. **LCLIntf's own surface is used zero times** — there
is no qualified `LCLIntf.` call in `dwsXPlatform.pas` either. It is load-bearing
only for a transitive re-export: `System.SyncObjs` is imported in the *non-FPC*
arm (line 71) while `TdwsCriticalSection` derives from `TCriticalSection`
unconditionally (line 99), so under `--mimic-fpc` the type has to arrive through
LCLIntf. Our `syncobjs` has a real `TCriticalSection`.

So "wants Lazarus" was a claim about an **import**, not about a dependency, and
what is actually left is an ordinary RTL gap ladder. That is the fact that
decided the split.

**The empty stub is the whole method.** It is a probe whose right answer differs
from the default: if LCLIntf had been supplying anything, an empty unit would
have named it in a list of unknown identifiers. It named none. A *shim* would
have proved nothing either way.

### The judgement

Two tickets, because the halves differ in **startability**, which is the one
property a shared row cannot represent:

- **[[feature-embed-dwscript-core]]** — 94 of 96 units, blocked on nothing but
  nameable RTL gaps, work available today. It takes corpus rung 4.
- **this ticket** — needs Delphi extended RTTI, which
  **fpc 3.2.2 does not have either**. Not startable.

One row carrying both ranks the startable half behind the unstartable one at a
single prio, and rung 4 of [[feature-pascal-corpus-expansion]] needs something a
session can actually be pointed at. Re-scoping alone would have left the corpus
rung linking to a ticket about extended RTTI.

### Two smaller things this turned up

**A citation that read as a receipt.** The done ticket says the Lazarus problem
was *"Recorded on [[feature-embed-dwscript-rtti]]"*. It was not — this file
contained no mention of LCL, Lazarus or Posix before today. The sentence was
written in the same breath as the intent and never became the write.

**The blocker had no row.** "Will not be until pxx has Delphi extended RTTI"
named no ticket, so the ranker saw prio 40 with `blocked-by: []`. Now
[[feature-b-delphi-extended-rtti-object-model]].

**And the measurement nearly went the other way.** Compiling from *inside*
`Source/` resolves no `unitalias` rows at all, because the manifest walk stops
before the cwd and a bare filename has no directory part — so the landed feature
looked broken for an hour. Only running its own `test/libmanifest` positive
control separated "feature is broken" from "probe is mis-invoked". Filed as
[[bug-p-a-manifest-is-skipped-in-silence-when-the-source-is-compiled-from-its-own-directory]].
