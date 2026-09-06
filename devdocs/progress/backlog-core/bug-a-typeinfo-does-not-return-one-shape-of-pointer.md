---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`TypeInfo(T)` returns two structurally different pointers depending on T. An ENUM resolves to the enum's own RTTI blob (what GetEnumName reads); every other type resolves to a TTypeInfo header (kind, name, DataPtr). Nothing in the type, the operator or typinfo.pas says which one you got, so a routine that reads one shape CRASHES on the other rather than answering wrongly — measured: `GetEnumName(TypeInfo(TRange1), 2)` on a subrange of an enum segfaulted, walking a member table over a subrange's typedata. That instance is fixed; the two-shapes fact is not, and the next alias or type family that reaches GetEnumName has the same crash waiting. THE `Ord(PTypeInfo(TypeInfo(TEnum))^.Kind)`-IS-AN-ADDRESS TELL IS RETIRED (frankS, 2026-09-06, on frankA's measurement): it was never the invariant, it was the SYMPTOM of the first instance, and it was written into this summary as though it were the property. It is ONE-DIRECTIONAL and the defect is not -- an enum ALIAS has a plausible small Kind and a record ALIAS has the RIGHT Kind, and a reader following the tell certifies both as clean. A one-directional tell on a two-directional defect is worse than none. THE INVARIANT THAT SURVIVES ALL THREE INSTANCES IS ABOUT THE SHAPE, NOT ANY FIELD: TypeInfo must return ONE kind of pointer, and the check a caller can actually run is `does the type I asked about answer the SAME pointer as the type it aliases` -- the five SAME rows of the census in bug-a-a-plain-type-alias-gets-its-own-rtti-blob-so-typeinfo-pointer-dispatch-misses, which is this ticket's acceptance test. TWO MORE INSTANCES ADDED 2026-09-06 (frankA), from the alias census: an ordinary ALIAS OF AN ENUM (TMyColour = TColour) yields a HEADER with Kind=1 named \"Integer\" instead of the enum blob -- the OPPOSITE direction to the subrange instance, so a fix that only detects \"blob where header expected\" misses it; and an alias of a RECORD yields a correct Kind=13 and SEGFAULTS on its own NamePtr, which the Kind tell cannot detect at all because Kind is right. The standing Ord(Kind)-is-an-address tell covers NEITHER. Meets bug-a-a-plain-type-alias-gets-its-own-rtti-blob-so-typeinfo-pointer-dispatch-misses in one table; fix neither without reading the other."
status: backlog
owner: unassigned
---

# TypeInfo does not return one shape of pointer

- **Found:** 2026-09-06 (frankS), fixing the subrange-as-a-type-name group
  ([[feature-pascal-corpus-fpc-testsuite]], tenum3) at `14e6ce592`. Filed at
  frankA's read and the coordinator's ask, because the CRASH is fixed and the
  FACT is not written down anywhere a future caller would look.
- **Measured at compiler `87f808d53396`** against fpc 3.2.2.

## The two shapes

`pasparser_expr.inc`'s TypeInfo arm has two exits:

- **legacy enum path** — `ASTLeft = -1`, `ASTIVal` = the enum type id. Emits a
  pointer to the ENUM's OWN RTTI blob. `GetEnumName` reads this.
- **everything else** — `ASTLeft = 1`, `ASTIVal` = a `RegisterTypeInfoReq` row
  (ORD / ARRAY / RECORD / CLASS / ALIAS). Emits a `TTypeInfo` header: kind at
  +0, name at +8, DataPtr at +16 (`rtti_emit.inc`).

`typinfo.pas` declares one `PTypeInfo` and one `GetTypeData`. Nothing marks
which shape a given `TypeInfo(...)` produced.

## Why it crashes instead of answering wrongly

```pascal
type TEnum2 = (zero, first, second, third);
     TRange1 = first..second;
begin
  Writeln(GetEnumName(TypeInfo(TRange1), 2));   { SEGV before 14e6ce592 }
end.
```

A subrange resolved down the ALIAS path, so `GetEnumName` was handed a
subrange's typedata and walked it as an enum's member table. fpc prints
`second`. Fixed by routing a subrange whose `AliasSemId` names an enum to that
enum's RTTI — **one caller, not the contract.**

## The standing tell, reproducible today

```pascal
Writeln(Ord(PTypeInfo(TypeInfo(TEnum))^.Kind));   { fpc 3, pxx an address }
```

Reproduces through the TYPE spelling, so it is not about
`TypeInfo(<variable>)`; that arm resolves to whichever path the type would.
`test_typeinfo_of_a_variable_answers_its_own_type` asserts pointer IDENTITY
between the two spellings and deliberately does NOT assert `Kind`, precisely so
this divergence is not imported into a file about something else — see the
comment there.

## The deliberate limit that ships with the fix

A subrange of an enum answers the **base enum's** RTTI, and the bounds are
**NOT narrowed**: fpc clips `MinValue`/`MaxValue` to `first..second`, we report
the full enum's. The member NAMES — what `GetEnumName` and every corpus caller
ask for — are identical either way, and no channel carries a narrowed range into
the legacy enum blob. Widen the day a row asserts the bounds; until then this is
a stated limit and not an unknown.

## The other half of the same contract

[[bug-a-a-plain-type-alias-gets-its-own-rtti-blob-so-typeinfo-pointer-dispatch-misses]]
(frankA, `f258d9a8f`) is this operator failing the same contract on the other
axis: **this row is two SHAPES for different types; that one is two POINTERS for
one type** — `TypeInfo(TMyInt) <> TypeInfo(Integer)` for `TMyInt = Integer`,
same name, same kind, different identity, so `if p = TypeInfo(Integer)` takes
the fall-through arm. Both are consumers relying on a property TypeInfo does not
actually provide, and a fix to either that does not know about the other can
make the other worse. Its constraint — a `= type Integer` DISTINCT type must
keep its own blob — bounds any collapse-the-blobs answer here too.

## What is NOT established

**How many readers assume a `TTypeInfo` header.** Nobody has counted, and this
row does not guess one. `GetEnumName`/`GetEnumValue` are the known enum-blob
readers; every other `typinfo.pas` entry point that takes a `PTypeInfo` is a
candidate and none has been probed. That census is the first increment, it is ONE census and not two -- the alias
row above needs the same enumeration for readers that compare pointer IDENTITY,
so whoever runs it should answer both -- and it decides whether the fix is "give the enum blob a real header" (changing every
existing reader) or "add an ENUM req category whose DataPtr points at the
existing blob" (changing GetEnumName only).

## A second and third instance, from the alias census (frankA, 2026-09-06)

Measured at `0e3558e5a4d4` while censusing
[[bug-a-a-plain-type-alias-gets-its-own-rtti-blob-so-typeinfo-pointer-dispatch-misses]].
One census, both questions — the two tickets meet in the same table and neither
should be fixed without reading the other.

**An ordinary ALIAS OF AN ENUM reaches this bug, not just a subrange.**
With `TMyColour = TColour`:

| | shape | `Kind` reads as | `NamePtr^` |
| --- | --- | --- | --- |
| `TypeInfo(TColour)` | enum blob | an ADDRESS | unreadable |
| `TypeInfo(TMyColour)` | **TTypeInfo header** | **1** | **`"Integer"`** |

So the alias does not merely get a *separate* descriptor — it gets one of the
**wrong shape and the wrong kind**, naming a type the program never mentioned.
`GetEnumName(TypeInfo(TMyColour), 0)` is handed a header where its `PEnumRTTI`
signature says blob. This ticket predicted *"the next alias or type family that
reaches GetEnumName has the same crash waiting"*; this is that alias, and it is
reached by the most ordinary spelling there is.

Note the direction is the OPPOSITE of the subrange instance already recorded
here: there, something that should have been a header was a blob; here,
something that should have been a blob is a header. **A fix that only teaches
callers to detect "blob where header expected" will not catch this one.**

**And a third shape failure, in the record family.** `TMyRec = TRec` yields
`Kind` = 13 — correct for a record — and then **segfaults on `NamePtr^`**, while
`TRec` itself reads fine. A descriptor that type-checks, reports the right kind
and crashes on its own name field is a shape failure the `Kind` tell cannot
detect at all, because `Kind` is right.

## The tell is retired, and how it got written is the point

**`Ord(PTypeInfo(TypeInfo(TEnum))^.Kind)` being an address is withdrawn as this
ticket's tell** (frankS, 2026-09-06, on the measurement above). Recorded as a
mistake rather than quietly replaced, at frankS's request, because the summary
read as though someone had checked that the tell generalises and nobody had:

> It was never the invariant. It was the SYMPTOM of my instance, and I wrote it
> into the summary as though it were the property. — frankS

It is **one-directional** and the defect is not. A checker built on it reports
both of the instances above as clean: the enum alias has a plausible small
`Kind`, and the record alias has the **right** `Kind` and fails on a different
field. **A one-directional tell on a two-directional defect is worse than none**,
because it converts "unmeasured" into "checked".

This is the *name is not the thing* failure in its usual clothes — the part you
sample confirms it. Same shape as `ArrLen > 0` the same day.

## The invariant that does survive all three instances

**`TypeInfo` must return ONE kind of pointer.** Not a property of any field:

| instance | what arrived | what was expected |
| --- | --- | --- |
| subrange of an enum (frankS) | a blob | a header |
| alias of an enum (frankA) | a header | a blob |
| alias of a record (frankA) | a header, structurally right, semantically empty | a header describing `TRec` |

Three failures, one cause: **every named type mints a descriptor and nothing
reconciles it with the type it aliases.** The record alias describing `Integer`
is what a freshly minted descriptor with no opinion says.

So the check a caller can actually run is not "is this `Kind` plausible" but
**"did the type I asked about and the type it aliases answer the SAME
pointer"** — which is the five SAME rows of the census in
[[bug-a-a-plain-type-alias-gets-its-own-rtti-blob-so-typeinfo-pointer-dispatch-misses]].
**That census is this ticket's acceptance test**; the `Kind` tell is not.

**A probe here must read `Kind` before `NamePtr`.** The first cut of the census
did not, segfaulted on row 6, and reported nothing about rows 7–13 — which is
where both of these live. A probe that dies partway through reads as a short
table rather than as an error.

