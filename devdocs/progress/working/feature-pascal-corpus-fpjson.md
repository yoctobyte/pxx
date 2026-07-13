---
prio: 58
---

# fpjson (fcl-json) — rung 2 of the Pascal OOP corpus

- **Type:** feature (compat — real-code validation of the OO surface)
- **Track:** P — Pascal frontend, tag: compat
- **Status:** working — in progress 2026-07-13. **Deep into the unit; ~20 walls cleared.**
- **Follows:** [[feature-pascal-corpus-fpcunit]] (rung 1 — DONE, compiles and runs)

## Why fpjson
Abstract base + polymorphic descendants (`TJSONData` → number/string/bool/null/array/object),
`class of` factory dispatch, owned-child lifetimes, and a byte-exact roundtrip oracle. Its own
suite is 12k LOC of fpcunit — which now RUNS, which is what makes this rung testable.

## Cleared so far (each landed green with its own regression)
Compiler:
- constant SET EXPRESSIONS (`ActualValueJSONTypes = ValueJSONTypes - [jtNull]`) — b281
- **unary `not` on an ARRAY ELEMENT / FIELD / DEREF was BOOLEAN, not bitwise** — silent wrong
  bit math, found writing set-difference in the compiler itself — b280
- `array[Boolean]` / `array[TEnum]` / `array[Char]` — an array indexed by an ordinal TYPE — b284
- SET-typed DEFAULT PARAMETERS (`Options: TFormatOptions = DefaultFormat`) — b282
- property REDECLARATION (`property Items;default;`) — b283
- initialised arrays of CLASS REFERENCES, const AND var — b285
- class-reference ops on ANY pointer node, and on TYPED metaclasses
- `array of const` LITERAL passed to a METHOD (all method call paths now share one builder) — b287
- value casts to an ordinal type NAMED BY AN IDENTIFIER (`WideChar(x)`) — b286
- `TypeInfo(TEnum)` intrinsic + TypInfo enum reflection — b288
- overload-aware metaclass-CAST constructor (`TFooClass(x).Create(args)`)
- a SELECTOR after an indexed-property read (`Self.Items[I].Clone`) — b289
- TVarRec's full union, with TYPED boxed members (`VExtended^` was tyUnknown → every overload
  of what it was passed to failed to match)

RTL (new units and surface):
- `lib/rtl/variants.pas` — VarType/VarIsNull/VarIsEmpty/VarIsNumeric/VarIsStr, Null/Unassigned
- `lib/rtl/contnrs.pas` — TFPObjectList, TFPHashObjectList
- `classes`: TStringStream
- `sysutils`: the exception hierarchy (EConvertError, EDivByZero, ...), StrToBool, StrToQWord,
  TryStrToInt64/QWord/Float, HexStr, StrPas/StrLen, sLineBreak, UTF8Decode/Encode,
  AnsiCompareStr/Text, UnicodeFormat, BoolToStr, ExceptClass, BackTraceStrFunc, TMethod
- `typinfo`: GetEnumName / GetEnumNameCount; GetEnumValue made case-insensitive (FPC parity)

## THE CURRENT WALL
```
pascal26: error: Expected: :=, but got: ... (in TJSONData.DumpJSON)
  near:  W  '":'  O  Items  I  DumpJSON >>> S  end
```
i.e. `O.Items[I].DumpJSON(S);` — a method call, WITH an argument, on an INDEXED PROPERTY, as a
statement, **inside a method that also has a nested procedure**.

**Every piece reproduces GREEN in isolation** and is regression-tested:
- a method call on an indexed property, as a statement — works
- ...with an argument — works
- ...implicit-Self (`Items[I].Dump`) — works
- a nested procedure inside a method, capturing the method's params AND reaching Self — works

So it is the COMBINATION, or something about fpjson's specific shape (TJSONData.Items has a
VIRTUAL getter and TJSONArray REDECLARES the property as `default`). **Do not guess** — this
is exactly the situation that ate four rounds in the TPoint hunt
([[project_dump_tokens_before_theorising]]). Cut fpjson.pp down until it flips, or dump the
tokens/AST at that call. The wide diagnostic window (`WriteTokenContext`, temporarily widened
to ±20 tokens) is what located it at all.

## Gate
`make test` + self-host byte-identical + cross.
