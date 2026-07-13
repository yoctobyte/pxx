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
