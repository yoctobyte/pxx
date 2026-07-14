---
prio: 55
---

# rtl-generics (Generics.Collections) — rung 3 of the Pascal OOP corpus

- **Type:** feature (compat — generics × classes × interfaces)
- **Track:** P — tag: compat
- **Status:** backlog — recon done 2026-07-13 night (rungs 1+2 are green: fpcunit
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

**The wall recon stops at: generics.defaults is built ON FPC-layout RTTI** —
PTypeInfo/PTypeData reflection to select comparers per TypeInfo(T), incl.
TypeInfo of GENERIC PARAMS. pxx's RTTI blobs are deliberately our own layout
(TypeInfo() is enum-only for exactly this reason). Options: grow a real
FPC-compatible TypInfo surface (big, cross-cutting — the same boundary as
feature-embed-dwscript-rtti), or a pxx-native Generics.Defaults implementation
(a FORK, which corpus rules resist). Decision needed before this rung
continues; helpers unit itself now compiles.

## User call 2026-07-14: decisions DELAYED. Analysis of where RTTI layout matters
Raw FPC TTypeData BYTE layout matters almost nowhere: consumers (generics.
defaults, fpjsonrtti, LFM streaming, mORMot-style serializers, script embeds)
read through the typinfo UNIT's record definitions + accessors (GetTypeData,
GetPropInfo, GetEnumName) — and those definitions live IN typinfo. So the
fork-free path when resumed: a FACADE lib/rtl/typinfo.pas declaring FPC's
record/API shapes backed by OUR blobs. The real compiler gap underneath is
TypeInfo(T) being enum-only — generics.defaults needs per-TYPE info blobs
(scalars/strings/records/classes, incl. generic params). Layout parity itself:
only needed for code doing pointer arithmetic past the published API (rare;
punt until a corpus target actually does it).
