---
prio: 58
---

# fpjson (fcl-json) — rung 2 of the Pascal OOP corpus

- **Type:** feature (compat — real-code validation of the OO surface)
- **Track:** P — Pascal frontend, tag: compat
- **Status:** working — 2026-07-13. **fpjson COMPILES AND PRODUCES CORRECT JSON.** The DOM, the
  formatter and every accessor are green. Remaining: the SCANNER's `\uXXXX` path needs UTF-16.
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

## fpjson WORKS

```
{ "name" : "pxx", "version" : 2, "ok" : true, "ratio" : 1.5,
  "list" : [1, 2, "three"], "child" : { "nested" : "yes" } }
```
Every accessor correct: Get / Strings / Integers / Floats / Booleans, nested objects, arrays,
IndexOfName, JSONType. fpjson.pp is used UNMODIFIED (888 procs).

### The last three, and every one was SILENT
- **Virtual CLASS METHODS bound statically.** `class function JSONType: TJSONType; virtual;`
  read through a base-typed reference ran TJSONData's base body and returned jtUnknown — so
  every `Get(name, default)` quietly returned the default. A class method's Self is the
  METACLASS, so IR_VIRTUAL_CALL cannot be reused (it loads the VMT from [Self+0], which on a
  blob is the name pointer). Lowered instead to `[[Self + 24] + slot*8]` + IR_CALL_IND —
  target-independent, no backend op. (b290)
- **A method's RETURN-TYPE class id was recorded at its BODY, not its DECLARATION.** So a
  method called before its own implementation appeared — ordinary inside one unit — had
  ProcRetRecId = REC_NONE, and a selector on its result degraded to a FIELD access. Every piece
  reproduced GREEN in isolation; only the ORDER made it fail, which is why it needed a
  token-level instrument to see. (b291)
- **Constant initializers ran AFTER unit initialization sections.** fpjson's initialization
  reads a class const to set up its separators — and read zeros. Every document it formatted
  came out with no braces, no colons, no commas: the structure right, the punctuation simply
  absent. A constant that does not hold its value until after the program starts running is not
  a constant. (b292)

Plus the property `index` specifier (b293) and runtime set members in `in` (b294), both from
the scanner.

## What is left
Only the SCANNER's `\uXXXX` escape path, which builds a UTF-16 surrogate pair
(`WideChar(u1) + WideChar(u2)`). That is a genuine string-model boundary, not a bug — see
[[feature-unicodestring-model]], which spells out what a real UnicodeString would take and why
faking it is exactly the failure mode this corpus keeps catching. **fpjson's DOM does not need
it**; only parsing JSON *text* containing `\u` escapes does.

## Next
Rung 3 — reassess. Likely `rtl-generics` (generic classes x interfaces x class constraints) or
`fcl-xml` DOM. Also now unblocked: fpjson's OWN fpcunit suite, since fpcunit runs.

## Gate
`make test` + self-host byte-identical + cross.
