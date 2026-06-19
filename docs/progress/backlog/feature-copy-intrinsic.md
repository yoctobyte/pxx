# `Copy` as a generic overloaded intrinsic (string + dynarray families)

- **Type:** feature (compiler)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, while delivering string `Copy` in lib)
- **Relation:** pairs with the lib `strutils` work (`lib/rtl/strutils.pas` already
  ships the interim AnsiString `Copy`); depends on **generics or builtin-overload
  support**. Sibling of the same-shape intrinsics `Delete` / `Insert` / `Concat`
  (see note below).

## Why the lib cannot finish this

`lib/rtl/strutils.pas` provides `Copy(s: AnsiString; index, count): AnsiString`
— good enough for the demos that copy substrings, and soon to be
`SetLength`-optimized (build the result once, no char-by-char append). But the
full FPC `Copy` is a **generic intrinsic overloaded over a type family**, which a
single non-generic RTL function cannot express:

1. **dynamic-array `Copy(arr, index, count)` → sub-array of `array of T`.** The
   real blocker: element-type-aware, generic over `T`. Not writable as one
   concrete RTL routine. Needs generics or a compiler intrinsic.
2. **2-arg form `Copy(s, index)`** = from `index` to the end (count defaults to
   the rest). Overload resolution on arity.
3. **string-family overloads:** `ShortString`, `UnicodeString` / `WideString`
   (if/when those types exist).
4. **call-site resolution by argument type:** pick the string vs dynarray
   meaning of `Copy` from the actual argument type.

## Scope

- Recognize `Copy` as an overloaded intrinsic resolved at the call site by
  argument type (string family vs dynamic array) and arity (2-arg vs 3-arg).
- dynarray form returns a fresh `array of T` (element-type-aware copy).
- Keep the lib `strutils.Copy(AnsiString)` working as the interim path; the
  intrinsic supersedes it for the generic cases.

## Siblings (same reasoning — mention so they aren't re-discovered)

`Delete(s/arr, index, count)`, `Insert(src, dst, index)`, and `Concat(...)` are
also intrinsics overloaded over the same string + dynarray families. They will
hit the identical "can't be one non-generic RTL function" wall. Fold them into
this work (or spin a sibling ticket) rather than re-filing each from a demo.

## Log
- 2026-06-19 — opened by track B. Interim AnsiString `Copy` lives in
  `lib/rtl/strutils.pas`; this ticket covers the generic intrinsic the lib can't
  express (dynarray `Copy`, 2-arg form, string-family overloads, by-type
  resolution).
