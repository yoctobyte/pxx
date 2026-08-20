---
track: P
prio: 65
owner: frank1-ACP
---

# rtl-generics (Generics.Collections) — rung 3 of the Pascal OOP corpus

- **Type:** feature (compat — generics × classes × interfaces)
- **Track:** P — tag: compat
- **Status:** working
  runs, fpjson's suite is 203/203).
- **Follows:** [[feature-pascal-corpus-fpjson]] (done). Parent umbrella:
  [[feature-pascal-corpus-oop]].

## Why this rung
~9.5k LOC (generics.collections/defaults/hashes/helpers/memoryexpanders): generic
classes, `IComparer<T>`/`IEqualityComparer<T>` interface constraints, class
constraints — the generics × classes × interfaces intersection nothing else
touches. Stage dir prepared: /tmp/generics-stage (symlinks + inc/), driver g1.pp
(TList<Integer> smoke).

## Walls cleared during recon (b329 batch, landed)
1. `{$I inc\file.inc}` backslash include paths (ExpandIncludes translates).
2. `rtlconsts` unit (minimal FPC-compat message consts, lib/rtl/rtlconsts.pas).
3. `array[Byte] of X` — small ordinal type as a whole index range.
4. PUInt8/PInt8/PUInt16/PInt16/PUInt32/PInt32 builtin pointer names.
5. LOCAL var-section initializers `var a: UInt32 = 1;` (ordinal/float consts via
   the LocalInit prologue machinery; STRING literals still unsupported there —
   they take a different decl path, small follow-up).
6. Compound-assign STATEMENTS `a += e;` (expression side + IR already existed
   for the C frontend).

## The current wall
`{$MACRO ON}` + `{$define mix_abc := <multi-line statement text>}` —
FPC compile-time TEXT MACROS, used by generics.hashes' bottom-up Jenkins mixer
(`mix_abc;` / `final_abc;` splice statement blocks). A lexer-level feature:
store the replacement text at `{$define name := ...}`, splice it when the bare
identifier appears. FPC also allows parameterless value macros. Scope carefully:
macros interact with the include expander and the token pre-scan.

## After that
Unknown — generics themselves. pxx has "generic class in program" support; a
full `TList<T>` with specialization-per-instantiation across UNITS is the real
test. Expect walls in: `generic TList<T> = class` header syntax, `specialize`
vs Delphi-mode implicit specialization, nested generic types
(TDictionary<K,V>.TPair), interface constraints, TArray<T> = array of T.

## Gate
Suite: rtl-generics has FPC tests (packages/rtl-generics/tests). Same recipe as
fpjson: stage dir + driver + tjrun-style walker once it compiles.

## Recon continued (same night) — b330 landed
7. `{$MACRO ON}` text macros: ExpandPasMacros textual pre-pass (elfwriter.inc,
   runs after ExpandIncludes; guarded so only value-define sources pay). Bodies
   flatten to one line, directives blank to spaces — line numbers preserved.
8. Int8/Int16/Int32 as value-cast names (OrdinalNameToTk).
9. RolDWord/RorDWord/RolQWord/RorQWord System rotates (__pxx soft-alias
   helpers in builtin, UpCase/Pos pattern; prescan pull).

## The NEXT wall (where this rung actually starts costing)
`type TValueAnsiStringHelper = record helper for AnsiString` — TYPE HELPERS
(generics.helpers.pas). A real language feature: helper method dispatch on
plain types, `Self` = the value. After that: the generic classes themselves
(TList<T>/TDictionary<K,V> across units, specialize, interface constraints).
Both are full sessions, not walls.

## Next-wall inventory (generics.defaults) — methods NAMED after TYPE KEYWORDS
`class function Integer(constref ALeft, ARight: Integer): Integer;` etc — ~30
each in TCompare/TEquals/THashFactory. Needs: member-NAME position accepting
type-keyword tokens (tkInteger_T/tkLongWord_T/...; NOTE their SVal is empty —
read via GetTokenStr, the class-body property path already does), impl headers
`class function TCompare.Integer(...)`, and call sites `TCompare.Integer(a,b)`
(selector paths guard on CurTok.Kind = tkIdent). Plus UNTYPED constref params
(`constref ALeft, ARight): Integer`). Type helpers are DONE through statics
(b331 v1+v2, see feature-pascal-type-helpers).

## Recon round 3 (b332 landed) — and THE architectural wall
10. `&keyword` escaped identifiers (lexer: '&'+letter = plain tkIdent, no
    keyword lookup; '&777' stays octal).
11. Methods NAMED after type keywords (`class function Integer(...)`) —
    IsMethodNameTok at decl/impl/call-site name positions; names via
    GetTokenStr (keyword tokens carry no SVal).
12. `class of` FORWARD references mint a forward class row.
13. PVariant builtin pointer name.

**The wall recon stops at: generics.defaults selects comparers through RTTI**
— PTypeInfo/PTypeData over TypeInfo(T), incl. TypeInfo of GENERIC PARAMS.
pxx's TypeInfo() is enum-only today. NOT a decision — see the plan below; no
fork, no byte-layout cloning.

## 2026-07-14 — NO DECISION NEEDED. Settled approach: facade typinfo over our own blobs

The apparent fork-or-clone dilemma dissolves on inspection. **Nothing real reads
FPC's RTTI bytes directly.** Consumers — generics.defaults, fpjsonrtti,
LFM/`TPersistent` streaming, mORMot-style serializers, the script embeds — reach
RTTI through the `typinfo` UNIT's record declarations and accessors
(`GetTypeData`, `GetPropInfo`, `GetEnumName`, `PropType`), and **those
declarations live inside typinfo itself**. So we supply typinfo.

Consequences:
- **No byte-layout parity.** We are free to keep our own blob layout.
- **No fork of Generics.Defaults.** The vendor source compiles unmodified
  against our typinfo.
- Layout only leaks if a library does pointer arithmetic PAST the published API.
  Rare; deal with it if a corpus target actually does, not before.

### The work (two items, both ordinary)
1. **Widen `TypeInfo(T)`** beyond enums: emit a per-TYPE info blob for scalars,
   strings, records, classes and (the one that matters here) GENERIC PARAMETERS
   at specialization time. This is the real compiler gap and the only
   interesting part. Track A/P.
2. **`lib/rtl/typinfo.pas` facade**: declare FPC's `TTypeKind`/`PTypeInfo`/
   `PTypeData`/`PPropInfo` API SHAPES and fill them from our blobs. Track B.
   (The existing typinfo already does exactly this for enums — GetEnumName /
   GetEnumValue / GetEnumNameCount — so this is growing a proven pattern, not a
   new one.)

Same facade unblocks [[feature-embed-dwscript-rtti]] and the RTTI->streaming->LFM
line, which is why it is worth doing properly rather than shimming per corpus.

## 2026-08-01 — item 1+2 LANDED: TypeInfo(T) widened + typinfo.pas facade

Both halves of the settled plan above are done and verified (self-host
fixedpoint + `testmgr --tier quick` green; `make test` running as the fuller
confirm since this touches shared RTTI emission).

**Compiler side (Track A/P, `compiler/defs.inc`, `symtab.inc`, `parser.inc`,
`ir.inc`, `rtti_emit.inc`, `compiler.pas`):**
- `TypeInfo(T)` now accepts scalars (Integer/Boolean/Char/Int64/QWord/Single/
  Double/Extended/...), `string`/`AnsiString`/`ShortString`, any user CLASS,
  and any user RECORD — not just enums. Enum `TypeInfo(TEnum)` is byte-for-byte
  UNCHANGED (still yields the bare `PEnumRTTI` address) specifically so
  fpjson's `GetEnumName`/`GetEnumNameCount` gate stays untouched — verified by
  a regression check in the smoke test below.
- New machinery: `RegisterTypeInfoReq` dedups each distinct (category, key)
  `TypeInfo(T)` use at parse time; `EmitTypeInfoHeaders` (rtti_emit.inc) runs
  right after `EmitRTTI` and builds one uniform 24-byte "PTypeInfo" header per
  request — `{Kind:Int64; NamePtr:PString; DataPtr:Pointer}` — with `Kind`
  mapped onto FPC's actual `TTypeKind` ordinals (`PxxTkToFPCKind`, kept
  faithful to FPC's declared order on purpose, even though no byte-layout
  parity is required — costs nothing, avoids surprises). `DataPtr` is nil for
  scalars, and for class/record points at the ALREADY-existing `UClsRTTIOff[ci]`
  blob (the same `TClassRTTI` / layout-descriptor typinfo already read via
  `AN_CLASSREF`) — no new class/record blob format, pure reuse.
- New sentinel base `TYPEINFO_REQ_DATAREF_BASE = 500000` (most negative of the
  data-ref sentinel family, tested first in `compiler.pas`'s post-EmitRTTI
  fixup pass — same pre-link-fixup convention as `CLASSREF_DATAREF_BASE` /
  `RECORD_RTTI_DATAREF_BASE` / `ENUM_RTTI_DATAREF_BASE`).
- **Generic parameters needed NO special handling.** pxx generics specialize
  by literal TOKEN-STREAM substitution (`SpecializeStream` in parser.inc) —
  `T` inside a template body is textually replaced by the concrete type's
  spelling before the parser ever sees the specialized body. So `TypeInfo(T)`
  inside `TBox<Integer>` is just `TypeInfo(Integer)` by the time the widened
  TypeInfo() parsing runs. Verified end-to-end with a hand-written generic
  class (see smoke test below): `TBox<Integer>.KindOfT` and
  `TBox<AnsiString>.KindOfT` each report the correct FPC `TTypeKind` ordinal
  for their specialization.

**Library side (Track B, `lib/rtl/typinfo.pas`):**
- Added `TTypeKind` (FPC's own 30-member enum, same declared order — cheap
  fidelity, not required by the "no parity" decision but avoids surprises for
  any vendor code doing `array[TTypeKind] of X` or a raw `Ord()` compare).
- Added `TTypeInfoHdr` / `PTypeInfo` / `PTypeData` (`PTypeData = PTypeInfo`
  for now — one header, no separate TTypeData split yet; see "Known gaps"
  below) matching the compiler's new header layout exactly.
- `GetEnumName`/`GetEnumNameCount`/the whole existing enum facade is
  UNTOUCHED — enum `TypeInfo()` still returns a bare `PEnumRTTI`, not this new
  header, on purpose (see compiler-side note above).

**Verified with hand-written smoke tests** (not yet checked into `test/` —
follow-up, see below):
```pascal
TypeInfo(Integer)  -> Kind=1  (tkInteger),  NamePtr^='Integer'
TypeInfo(Boolean)  -> Kind=18 (tkBool),     NamePtr^='Boolean'
TypeInfo(TAnimal)  -> Kind=15 (tkClass),    DataPtr -> the class's real TClassRTTI (GetClassName works through it)
TypeInfo(TPoint)   -> Kind=13 (tkRecord)
TypeInfo(TColor)   -> unchanged PEnumRTTI path, GetEnumName/GetEnumNameCount still work (regression check)
generic TBox<T>.KindOfT calling TypeInfo(T):
  TBox<Integer>.KindOfT    = 1  (tkInteger)
  TBox<AnsiString>.KindOfT = 9  (tkAString)
```

**Process note:** briefly mis-suspected `case x of Ord(EnumConst): ...` was
broken in this compiler and reflexively rewrote two functions to if/elseif
chains as a "workaround" without testing the actual claim first. Caught (by
the user) before it shipped: a 4-line repro proved `case`/`Ord()` labels work
completely correctly, and the real error was an unrelated `const`-declared-
inside-a-`var`-block syntax mistake in `defs.inc`. Reverted to the natural
`case` form. No compiler bug here, no ticket needed — noted only so the
mistake (reasoning instead of measuring) isn't repeated.

### Known gaps / natural follow-ups (not blocking, noted for the next session)
- **No `TTypeData` fields beyond `DataPtr`.** `GetTypeData` doesn't exist yet
  as an FPC-shaped function (min/max/ordinal size for scalars, `PropCount`
  etc for classes read straight off the class blob today). Add when a real
  corpus target reads a specific field FPC's `TTypeData` has and ours
  doesn't.
- **generics.defaults itself not yet retried.** This session's remaining
  budget went to verifying the widening in isolation (hand-written smoke
  tests + the generic-specialization check above) rather than restaging
  `/tmp/generics-stage` (which no longer exists — `find` on this box turned
  up nothing) and re-running the vendor tree. generics.defaults expects
  `ATypeInfo.Kind` as a DIRECT field read (confirmed by reading
  `packages/rtl-generics/src/generics.defaults.pas` from a local FPC source
  checkout) plus `array[TTypeKind] of TInstance` lookup tables and
  `GetTypeData(ATypeInfo)` for extra fields (e.g. ordinal size) — the `Kind`
  field and the `array[TTypeKind]` shape are both now supported by this
  landing; `GetTypeData` beyond `DataPtr` is the likely next wall. Re-stage
  per `tools/install_lib_candidates.sh` and retry as the next step.
- **No `test/test_typeinfo_widen*.pas` checked in yet.** The smoke tests
  above were hand-run from `/tmp` scratch, not committed as a gated regression
  test. Should land as a real `test/` file wired into `testmgr` before this
  ticket is considered done, so the widening itself is gated going forward
  (not just fpjson's enum-only regression).
- `test-fpjson` SKIPped locally (no fcl-json tree staged on this box —
  `tools/install_lib_candidates.sh fcl-json` was not re-run this session) so
  the "fpjson stays green" claim above rests on the unchanged-enum-codepath
  argument + the regression check in the smoke test, not a fresh fpjson run.
  Track T's watcher (or the next session, if it re-stages fcl-json) should
  confirm.


## 2026-08-16 — the ungated claim is now gated

The "Known gaps" entry above said the widen test was never checked in. Half
right, and the wrong half was the dangerous one: the file **was** committed with
the feature (`95007e237`) — it was wired into **no target**, so nothing had run
it for two weeks. A file in `test/` is not gated until a line in the Makefile
runs it; `test-core` enumerates its tests explicitly, it does not glob them.

Wired into `test-core` beside its enum sibling (`test_typeinfo_enum_b288`), same
`-Fulib/rtl -Fulib/rtl/platform/posix` flags. The test is self-checking — it
`Halt(1)`s on the first wrong `Kind` and prints `test_typeinfo_widen: OK`
otherwise — so the assertion is one line. Verified green under both HEAD and the
pinned binary; `gate.sh quick` GREEN.

So the widening claim now rests on a gated test rather than on an
unchanged-codepath argument. **`test-fpjson` is still SKIPped on this box** (no
fcl-json tree staged), which is the remaining half of that gap — it needs
`tools/install_lib_candidates.sh fcl-json` re-run here, or Track T's watcher to
confirm it elsewhere.

## 2026-08-16 — recon round 4: generics.defaults, four constant-initializer walls cleared

Re-staged rtl-generics (symlinked from the local FPC checkout; the script has no
rtl-generics target — it comes from `/home/rene/src/fpc-source`) and drove
`uses generics.defaults` until the wall moved. It moved four times.

**The ticket's stated wall was wrong, and cheaply so.** It named `{$MACRO ON}`
text macros as what generics.defaults dies on. The macros expand correctly. A
13-line repro with no macros in it fails identically — the real wall was that a
typed record constant accepted ordinals and `nil` and nothing else.

The misleading part is the diagnostic. `expected field name in record constant`
points at the VALUE, one field past the actual gap, because ConstEval can neither
evaluate nor CONSUME a string literal or an `@`, so the field loop desyncs by one
and blames whatever token it lands on. It reads as a bug in the field-list parser
and is nothing of the kind.

### Cleared (landed, each with a differential test vs fpc 3.2.2)

| # | wall | commit |
| --- | --- | --- |
| 14 | string / `@var` / `@proc` as a record-constant field value | `406a40dfa` |
| 15 | `@TClass.Method` — method code address via the type name | `6e87c872e` |
| 16 | (regression from 14) string arm must key on the field TYPE | `9cf91cf8d` |
| 17 | `@` forms in a SCALAR const and an ARRAY-of-record element | `a43bd4d21` |

Line 379 → 388 → 411 → 445 → 525.

**Item 14's real content: the emitter was never the gap.** Init kinds 1
(AN_STR_LIT), 2 (AN_PROCADDR) and 4 (AN_ADDR of an ident) were already
implemented and already exercised — by `cparser.inc`, for C struct initializers.
Same shared emitter, one frontend wired to it and the other not, so C could put a
function address in a struct initializer while Pascal could not put one in a
record constant. The fix was parser-side only.

**And it is FOUR parse paths, not one.** Scalar record field, array-of-record
field, scalar typed const, plus the routine-local twins — each had to be told
separately, and fixing the first did not make the others work. The corpus found
each by moving the wall; I did not predict any of them. All four now route
through one `TryParseInitValForm`, so the next value form is added once.

**Item 15** was refused as `cannot call non-static method on class type
directly` — a CALL error on an expression that never asked to call. A class type
is not in the sym table, so `@TB.Method` fell past every arm of the `@` handler
into the lvalue path; the `@` was still on the stack, unexamined. With no object
there is nothing to dispatch on, so it yields the static address of that class's
own body even for a virtual method, matching FPC — which is precisely what makes
the idiom useful, since it is how a VMT is built by hand.

**Method names that are type keywords** (`@TCompare.Single`) needed
`IsMethodNameTokAt`, an index-addressed lookahead form of the existing
`IsMethodNameTok` sharing its token set. Note the measurement mattered here:
the failing member was `Single`, not the `Int8` the ticket's own inventory would
have led me to fix — `Int8` already worked.

### The current wall (525) — measured, and NOT what the message says

```
error: base type not found: THashService$TDelphiHashFactory
  near: TDelphiHashFactory class >>> THashService$TDelphiHashFactory private
```

First read as "a class nested inside a class, used as a base type". That is
wrong, and worth recording as a misread rather than quietly corrected: `$` is
pxx's SPECIALIZATION mangling, not nesting. The construct is
`THashService<T: THashFactory> = class(THashService)` — a generic class whose
base is the same-named NON-generic class.

Narrowed with controls: a constrained parameter works, generic inheritance from
a differently-named base works, and the pair fails with **no inheritance at
all**. So the wall is that a generic and a non-generic class cannot share a
name — pxx keys a class by name with no arity component, so one row overwrites
the other. Filed as
[[bug-p-a-generic-and-a-non-generic-class-cannot-share-a-name]] (p50), with the
scope note that the real shape is arity-overloaded class names (FPC's
`TDictionary` / `TDictionary<K,V>`), not a guard for this one pair.

**CLEARED 2026-08-17** in `eda43dea7` — and it was not a name table. Two
unrelated defects wore one symptom: a bare `X.M` impl header was handed to the
template on a name match, and `SpecializeStream` rewrote the base-class
reference so the specialization inherited from itself. Two controls separated
them; the filed name-table scope was an inference from the error text and wrong.
See that ticket for the record.

### The wall now (635)

```
error: unknown type: array
  near: FEqualityComparer_Pointer_Instance Pointer FEqualityComparerInstances >>> array TTypeKind
```

An inline `array[TTypeKind] of ...` type in a class FIELD declaration —
an anonymous array type where only a named one is accepted. Unrelated to
generics. Not started.

### Side finding, filed separately

Calling straight through a procedural-type cast — `TSelfFn(V.Field)(o)` — is
`unexpected token`; assigning the cast to a variable first works. Hit twice while
writing these repros. Not folded in; see
[[bug-p-cannot-call-directly-through-a-procedural-type-cast]].

### Note on the fpcunit/fpjson claim

Untouched by this session and still resting on the argument recorded above, not
a fresh run: `test-fpjson` is still SKIPped on this box (no fcl-json staged).

### Wall 18 (line 635) — HALF cleared 2026-08-20 (frank3)

The ticket named the wall as `array[TTypeKind]` "in a class FIELD declaration".
Varying the shape showed that is two separate gaps wearing one error, and only
the first is fixed here.

**Gap 1 — an ordinal TYPE as a whole array index in a FIELD. FIXED.**
`var F: array[TKind] of Integer` already worked: the var section parses bounds
through `ParseArrayDimBounds`, which accepts `tkBoolean_T`, `tkChar_T`, a small
ordinal (`array[Byte]`) and an enum type name as the entire index range. The
three FIELD sites each carried their own inline `loVal := ConstEval; Expect('..');
hiVal := ConstEval` copy, so a shape the var section took happily answered
`not a constant` in a record or class field. Exactly the double-case
`devdocs/dev/normalise-dont-special-case.md` is about — except it was a
*quadruple* case, and the first fix (the class-field site) left the record-field
copy failing, which the new test caught.

All three now call `ParseArrayDimBounds`, dim 1 and the comma dims alike:
`parser.inc` class field ~28290, record field ~26291, and the N-D field site
~26854. Test `test/test_field_array_ordinal_index_b388.pas` (self-checking, FPC
3.2.2 as the oracle) covers `array[TKind]` / `array[Byte]` in a record and
`array[TKind]` / `array[Char]` / `array[Boolean]` / `array[TKind, 0..1]` in a
class; it is wired into `test-core` next to `test_typeinfo_widen`. Gate at this
sha: `make compiler/pascal26` converged, `tools/gate.sh quick` GREEN.

**Gap 2 — `class var` takes no array at all. NOT fixed, and one arm is silent.**
The wall's real field is in a `private class var` section, and that branch
(`parser.inc` ~27726) is just `fTk := ParseTypeKind; fRec := LastTypeRecId;`
followed by `AllocVar`. Measured against the self-hosted binary from this tree:

| class var form | today |
| --- | --- |
| `array[0..3] of Integer` (inline fixed) | `unknown type: array` |
| `array of Integer` (inline dynamic) | `unknown type: array` |
| `TA` where `TA = array[0..3] of Integer` | **compiles as a scalar**, fails later at the use site |
| `TD` where `TD = array of Integer` | **compiles as a scalar**, fails later at the use site |

The bottom two are the dangerous ones: a wrong TYPE accepted silently, with the
diagnostic landing somewhere else entirely.

This is deliberately NOT microfixed into a fifth copy of the bound parser. The
class-var branch needs the var section's whole descriptor+alloc machinery
(`isArr`/`isDyn`/`arrLo`/`arrHi`/`ndCnt`, named-alias resolution, then
`AllocArray`/`AllocDynArray` instead of `AllocVar`) — that lives inline in
`ParseVarSection` (`:24622`, alloc loop ~24925-24990) and wants extracting into a
shared "parse a variable's type" + "allocate from the descriptor" pair, which is
the overhaul, not this session. Banked here per
`devdocs/dev/root-cause-over-microfix.md`; the wall at 635 has NOT moved yet.

### Side findings measured here, not yet filed

- `SizeOf(<record or class field that is a fixed array>)` returns the ELEMENT
  size, not the array's: pinned v368 prints `4 4 12` where FPC 3.2.2 prints
  `12 12 12`. Pre-existing, unrelated to the above, and a silent wrong value.
- `FindTypeAlias failed to find puint8! AliasCount=36` is printed to stderr
  during the generics.defaults drive without stopping compilation.

## Lock released — 2026-08-20 (hardware loss, not a decision about the work)

The session holding this ticket (`frank3`) ran on the workstation **borg**,
whose PSU failed on the morning of 2026-08-20 and took a household fuse with it.
Borg is down for several days; its working tree — including anything uncommitted
— is gone, so **nothing of this ticket is in flight anywhere**.

Moved `working/` → `unfinished/` on the owner's instruction: *"any ticket
claimed as 'working on' is now invalidated."*

**Re-claiming this one needs a rebuild first:** the recon above stands on a stage
directory at `/tmp/generics-stage` (symlinks + `inc/`, driver `g1.pp`) that lived
on borg. It is gone twice over — dead machine, and `/tmp` besides. Recreate the
stage before trusting any wall count, and re-verify the cleared walls against
master, since the walls landed as pushed commits but the notes describe a tree
that no longer exists.

## Wall 18 cleared, then three more — 2026-08-20 (frank1-ACP)

Stage rebuilt on plexus (no FPC source on this box): `packages/rtl-generics/src`
only, 8 files / 12,487 lines, fetched at `release_3_2_2` from GitLab into the
session scratchpad with a `PROVENANCE.md`. Driver unchanged in spirit — `g1.pp`
is now `uses generics.defaults`, which is the first unit of the chain.

Walls fell in a row once the stage was back. Each was measured by re-driving
`g1.pp` after a `make compiler/pascal26`, so the line numbers below are the
successive stopping points of the SAME compile:

- **635 — `unknown type: array` on a class-var array** (wall 18, the one banked
  above). Cleared by the `ParseDeclTypeDesc` / `AllocFromDeclTypeDesc` split;
  see [[bug-p-a-class-var-takes-no-array-type-and-a-named-one-is-silently-a-scalar]].
- **769 — `too many generic templates`.** `MAX_TEMPLATES = 16` was a per-COMPILATION
  counter, not per-unit, so every template a program transitively `uses` shared
  it; generics.defaults alone declares well past 16. Raised to 128 (and the
  specialization/pending/generic-func counters with it). Cost measured, not
  guessed: BSS 211,128,564 -> 211,176,708 = **+48 KB**, because a template row is
  `{name, tok start, tok count}` and the parameter names live in a parallel
  string table. The megabyte-scale constant in that family is
  `MAX_TEMPLATE_TOKENS`, which was left alone.
- **985 — `base type not found: TOrdinalComparer`**, i.e. a generic inheriting a
  generic with the parameters forwarded. This was the real feature gap and took
  the rest of the session; write-up below.
- **1270 (current) — `absolute: unknown variable Self`.** `var p: PFoo absolute
  Self;` inside a method. New wall, in the implementation section — a different
  and much smaller gap than the last one.

### The feature: nested generic specializations

`generic TDer<T> = class(specialize TBase<T>)` — and the same shape as a field
type, and the mode-Delphi spelling `TDer<T> = class(TBase<T>)` — did not compile
at all. Neither did the two-parameter or three-deep forms. Root cause, measured
rather than reasoned (`--debug`'s `TEMPLATE`/`DGEN` traces, plus a new `SPEC`
trace added alongside them):

The generics machinery is token rewriting. A CONCRETE use inside a template
(`specialize TBase<Integer>`) already resolved, because `DelphiRewriteGenericUses`
sweeps the stream before the enclosing template captures it, mints `TBase$Integer`
and inserts the alias declaration. The PARAMETER form cannot resolve there —
`TBase$T` is not a type, and what `T` is only becomes known when the OUTER
template is specialized. The old code said so explicitly and gave up:
`{ specB paramform (inside a later generic body): leave untouched }`.

So it is resolved at the moment it becomes knowable. `ParseSpecialization` now
walks the template body for `specialize NAME<args>` groups, maps each argument
through the substitution it is about to apply, and mints the same alias name the
concrete path would have. Missing prerequisites mean the declaration cannot be
bound yet — a parent must exist before its child — so the whole declaration is
**deferred**: emit `TBase$Integer = specialize TBase<Integer>;` followed by a
fresh copy of the declaration we were in the middle of, and hand back to the
type-section loop. It parses the prerequisite (deferring again if THAT nests, so
a chain unwinds), then re-parses ours, which now finds the alias registered.
Termination is by construction: the retry mints the identical name and finds it.
`SpecializeStream` then collapses each group to the single alias identifier, so
the body it inserts speaks the ordinary non-generic surface.

Per `devdocs/dev/normalise-dont-special-case.md`, the mode-Delphi surface got no
resolver of its own: `TBase<T>` is rewritten INTO `specialize TBase<T>` and falls
into the same path. That required correcting what the Delphi rewrite does with a
parameter-spelled group, and the correction is the interesting part:

- It used to strip the `<T>` unconditionally, which is right for a method
  IMPLEMENTATION header (`function TBase<T>.Get`) and wrong everywhere else — a
  type reference was left as a bare template name, which is exactly the
  `base type not found` at 985. Now the strip is keyed on the group being
  followed by `.`, the one place it means "this template's own methods".
- The "is this group parameter-spelled?" test was ALL-or-nothing, so
  rtl-generics' partial specialization
  `TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>)`
  — which mixes a parameter and a concrete type in ONE group — took the concrete
  path and minted the nonsense specialization `TGStringComparer$T$TDelphi...`,
  whose body then reported `unknown type: T` from the far side of the unit. Now
  ANY parameter name anywhere in the group makes the whole group deferred, and
  the match is by name against any parameter rather than by position (`TBar<V, K>`
  forwards the same names in the other order).
- Template lookup by name is now ARITY-AWARE. Arity overloading (`TD`, `TD<K>`,
  `TD<K,V>` — test_generic_name_overload.pas) used to work by parse-order
  accident: a concrete use's alias declaration is inserted directly behind its
  own template and so is parsed before the next arity is even captured. A nested
  prerequisite is emitted much further down the stream, where every arity is
  visible at once, and the name-only lookup took the last one.

**Regressions:** `test/test_generic_inherit.pas` (objfpc) and
`test/test_generic_inherit_delphi.pas` (mode Delphi) — a three-deep forwarded
chain, a two-parameter generic base, a nested generic as a field type, and the
method implementations of each. Output verified **identical under fpc 3.2.2**.
Both registered in the Makefile.

Gate: `make compiler/pascal26` converged in 1 round; `tools/gate.sh quick` GREEN.

## Walls 19-21 cleared — 2026-08-20 (frank1-ACP)

Wall progression this pass: **1270 → 46 → 964 → 2179**. Three fixes landed
together, all found by driving `generics.defaults` with `$(PXX_STABLE)`; each
reduced to a minimal repro and diffed against fpc 3.2.2 before the fix.

### 19. a bodyless generic class swallowed the rest of the type section
`ParseGenericTemplateNamed` opened the capture at `depth := 1` and counted down
to a matching `end` — but a class declaration need not HAVE a body.
rtl-generics' one-liner

    TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>);

has no `end` at all, so the capture ran on and took the next 126 source lines
into the template (`--debug` showed `TEMPLATE TGStringComparer startTok=49657
endTok=50397 endLine=1119` for a declaration that ends on line 993). The damage
surfaced far downstream as `absolute: unknown variable Self` at line 1270 —
which is why every isolated repro of *that* construct passed. Measured, not
reasoned: the `TEMPLATE` trace named the real boundary in one run.

Fix: detect the three bodyless forms up front — `class;`, `class(Parent);`,
`class of T;` (and the same for `interface`) — and end the capture at the `;`.
Only a real body goes through the depth count. The non-generic path already
handled all three, so this was the generic path growing a second, worse copy of
"where does a class declaration end". Regression:
`test/test_generic_bodyless.pas`, with a following declaration as the canary.

### 20. an interface method could not carry a directive
The interface member loop had **no** directive handling — it read the signature,
ate the `;`, and expected the next `procedure`/`function`/`end`. Generics.Defaults'
very first declaration is `function Compare(constref Left, Right: T): Integer;
overload;`, so the parse stopped on line 45 of a 2400-line unit.

Fix: `EatIntfMethodDirective` — `overload`, a calling convention, and the hint
directives, all parse-and-ignore (an interface method is abstract and virtual by
definition; overload resolution is signature-keyed; pxx has one internal calling
convention). Guarded like `IsCallConvDirectiveTok`: these words are not
reserved, so one is recognised only where a `;` (or `deprecated`'s message
string) follows.

**And the root cause behind it** — this was the *fifth* place in `parser.inc`
that spells out "consume a method directive", and they had drifted: the
implementation-side loop knew `cdecl` and `register` but not `stdcall`, so
`procedure TC.Poke; stdcall;` parsed in the class body and then died on its own
body's header (`<scratchpad>/gen/rj.pas`). The class-body loop already used the
shared `IsCallConvDirectiveTok`; the record-method loop, the routine pre-scan
and `ParseSubroutine` each had their own list. All five now go through the one
predicate, so adding a convention is a one-line change in one place.
`normalise-dont-special-case`: three mechanisms for one concept was the design
flaw, and the sibling arms were exactly where the bug was.

### 21. a nested-generic prerequisite queued twice = duplicate class
The defer-and-retry mechanism from wall 18 emits one alias declaration per
prerequisite. rtl-generics reaches `TCustomComparer<string>` through **both**
`TGStringComparer` and `TOrdinalComparer`, so two deferrals queued their own
copy of the same alias and the second was diagnosed as a duplicate class.

Fix: at `ParseSpecialization`, a name that already names a specialization of the
**same template with the same arguments** is an exact re-statement — the alias
name is minted from exactly those — so consume it as a no-op. A collision with a
different template or different arguments still falls through to the ordinary
duplicate-class error. Regression: `test/test_generic_nested_diamond.pas`.

### Gate
`make compiler/pascal26` converged in 1 round; `tools/gate.sh quick` GREEN
(self-host fixedpoint 91s, testmgr quick 10s, FPC seed canary).

### Filed while here (not fixed)
- [[bug-p-interface-method-overload-picks-the-first-slot]] — an interface method
  is selected by declaration slot, not by argument type, so a call to the wrong
  same-named overload returns a silently wrong value. Found writing
  `test_interface_directives.pas`; the test deliberately avoids two same-named
  interface overloads so it does not freeze the wrong expectation.
- [[feature-p-nested-type-method-implementation]] — the next wall (line 2179):
  `class function TComparerService.TInstance.Create(...)`, a method
  implementation qualified by outer class AND nested type. The declaration side
  parses; the implementation header does not.
