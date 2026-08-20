---
prio: 50
owner: claude-acp
---

# `TypeInfo(T)` for every type, not just enums

- **Type:** feature (RTTI — Track A/P)
- **Status:** working
- **Blocks:** [[feature-pascal-corpus-generics]] (generics.defaults selects a
  comparer per TypeInfo(T), including TypeInfo of a GENERIC PARAMETER),
  [[feature-typinfo-facade-unit]], and behind those the RTTI->streaming->LFM
  line and [[feature-embed-dwscript-rtti]].

## Today
`TypeInfo(X)` accepts ENUM types only — deliberately: we emit one blob per enum
type (name, count, member names) and refused everything else rather than hand
back a blob whose layout is ours while pretending it is FPC's. That refusal was
right, and it stays right; what changes is that WE now supply the typinfo unit
that reads the blobs ([[feature-typinfo-facade-unit]]), so our layout is fine
and the only thing missing is the blobs themselves.

## The work
Emit a per-TYPE info blob for the kinds real code asks about:
- ordinals (with their sub-kind + range), Char/Boolean
- floats (with the float sub-kind)
- strings (short/ansi), sets, arrays (element type + length), dyn arrays
- records (size; field walk if/when a consumer needs it)
- classes (we already have the class RTTI blob — point at it) and metaclasses
- **generic parameters at SPECIALIZATION time** — `TypeInfo(T)` inside a
  `TList<Integer>` body must yield Integer's blob. This is the interesting part
  and the reason the ticket exists.
- interfaces, method pointers: only when a consumer needs them.

Interned per type, addressed like the enum blobs (data-ref sentinel patched at
link time), so the cost is paid once and only by programs that ask.

## Gate
`make test` + self-host byte-identical; a b-test that reads TypeInfo of each
kind through the facade unit; fpjson suite stays green.

---

## Progress — 2026-08-20 (Track A)

Landed in three increments, each gated `gate.sh quick` GREEN and pushed. Every
kind below was diffed against an **FPC 3.2.2 oracle**, not recalled; the two
places where FPC's answer was not the obvious one are called out.

### 1. `TypeInfo(Byte)` answered `Integer` — fixed

Not a missing kind, a **wrong answer**, so it came first. `byte` and `integer`
are two spellings of one token kind (`tkInteger_T`), and the type-keyword arm
switched on the kind, so it could not tell them apart — while the identical
`TypeInfo(UInt8)`, an ordinary `tkIdent` resolved by NAME, had always said
`Byte`. Resolves from the spelling now (`OrdinalNameToTk` first, kind switch
only for the keywords with no ordinal name).

Underneath it was a second, older defect: `tiName` read `GetTokenStr(TokPos)`,
one token PAST the type name (`Next` reads `Tokens[TokPos]` then increments),
so it held `)`. Invisible because `tiName` fed only the "not supported" error
and no branch reaching that error had assigned a kind.

### 2. Named structural types — `TYPEINFO_REQ_CAT_ALIAS`

`TSub = 1..10` (1), `TSet = set of TEnum` (5), `TProc = procedure(x: Integer)`
(23), `TMeth = procedure(x: Integer) of object` (6), `TStr20 = string[20]` (7),
plain rename `TMyInt = Integer` (1). All six were a hard refusal. They were
already in the alias table with everything needed, so this is one new
TypeInfoReq category keyed by the alias row, consulted as a LAST resort after
every builtin spelling — nothing that resolved before resolves differently.

Two of those kinds need more than `AliasTk`: a subrange and a `string[N]` both
carry an ordinary scalar tk (`AliasIsSub` / `AliasStrCap` separate them), and a
method pointer and a plain procedural type both carry a signature (only
`tyRecord` vs `tyPointer` separates the 16-byte `{Code,Data}` pair from a bare
code address).

**The name rule is what guessing would have got wrong.** FPC gives a type its
own name when the type is DISTINCT, so `TSub` reports `TSub` — but the plain
rename `TMyInt = Integer` reports `LongInt`, the BASE type's name, not
`TMyInt`. We do not track `type X = type Y` distinctness, so it is approximated
by structure: an alias that DEFINES something keeps its name, a plain rename
passes through. That reproduces every measured case.

### 3. Named array types + the builtin non-ordinals

`TArr = array[0..3] of Integer` (12), `TDyn = array of Integer` (21),
`TArr2 = array[1..2, 1..3] of Byte` (12 — a multi-dimension array is still ONE
tkArray). Arrays keep their own name table (`ArrType*` / `FindArrayType`), not
the alias table, so they get their own category; `ArrTypeIsDyn` is the whole
kind decision.

Same increment fixed a **duplicate-table** defect this path was carrying: it
kept a PRIVATE subset of the builtin-name table (the float family and the
strings, nothing else), so `TypeInfo(Pointer)` and `TypeInfo(Variant)` were
refused while `SizeOf` of the same names worked — exactly the defect
`BuiltinTypeNameTk`'s own header comment describes SizeOf having had. It now
defers to that one table (normalise-dont-special-case).

The string rows stay explicit above that call, deliberately, and the reason is
written at the call site: `BuiltinTypeNameTk` reports the internal type TAG a
`string` carries (`tyString` unmanaged), while RTTI has to report the string
MODEL the program observes — and pxx's `string` is pointer-sized (`SizeOf` = 8)
and grows past 255, **measured**, i.e. an AnsiString. Deferring those rows would
report `ShortString` for a type that is nothing of the kind.

### Escalated, not guessed

`decide-typeinfo-scalar-name-spelling` (Track U): we report `Integer` where FPC
reports `LongInt`, because pxx has `tyInteger` and `tyInt32` as separate kinds
where FPC's `Integer` IS `LongInt`. Cosmetic today — nothing branches on the
string — but it is a visible parity gap in a compat-sensitive API and the
recommendation is written up there.

### Filed, not edited

`bug-n-typeinfo-reads-the-wrong-token-and-switches-on-kind` (Track N):
`compiler/pyparser.inc` carries a copy of the same block with BOTH defects from
increment 1. It is Track N's file and N work is deferred, so it is handed off
rather than half-applied.

### Tests

- `test/test_typeinfo_scalar_names.pas` — the byte/integer pair that makes the
  kind-switch bug visible, plus the scalar set. Its `string` row matches FPC
  under `{$H+}` (pxx's string model); bare `-Mobjfpc` makes `string` a
  ShortString and is the WRONG oracle for that row — noted in the Makefile so
  it does not get "corrected".
- `test/test_typeinfo_named_types.pas` — the six named structural types.
- `test/test_typeinfo_array_pointer.pas` — arrays plus Pointer/Variant.

All three are refused outright by the pinned binary, so each one bites.

### Still open (the ticket stays in working/)

- **`DataPtr` / `TTypeData` payloads.** Every new category writes a nil
  `DataPtr` — kind and name only. The data is all recoverable when a consumer
  needs it (`AliasSubLo`/`Hi` for a subrange's bounds, `AliasElemTk` for a
  set's element enum, `ArrTypeElemTk` / `ArrTypeDimLo` / `ArrTypeDimSpan` for
  an array's element type and bounds), so this is emission, not discovery.
  Nothing in the corpus reads it yet — do it when something does.
- **Interfaces (14) and metaclasses (28).**
- **`Currency` (4).** pxx has no `tyCurrency` at all; this is a type-system
  item, not an RTTI one.
- **`PChar`** and pointer aliases generally — check whether `FindTypeAlias`
  reaches them or whether the pointer-alias path needs its own category.
- **Generic parameters.** The ticket calls this the interesting part, and it
  needs no separate path: pxx generics substitute the type parameter's token
  TEXTUALLY before the parser sees it, so `TypeInfo(T)` inside a specialized
  body is already `TypeInfo(Integer)` by then. Worth an explicit test before
  claiming it.
