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

## fpjson's OWN suite (testjsondata.pp, 4138 lines) — long tail, no blocker
Reachable because fpcunit runs. Walls cleared FOR the suite, each a real feature:

| landed | what it was |
| --- | --- |
| b295 | `for F in Data` — a container EXPRESSION (a property) with GetEnumerator |
| b296 | class-reference ops chained after a value (`d.M.ClassName`) — were silently DROPPED |
| b297 | a PARENTHESISED expression keeps its class id (`(b as T)[i]`, `(b as T).ClassName`) |
| b298 | `array of const` literal to an OVERLOADED ctor — silently passed GARBAGE |
| b299 | CLASS PROPERTIES through the class name (also resolves feature-pascal-class-property) |
| b300 | **FreeAndNil SILENTLY SKIPPED THE DESTRUCTOR** |

b300 is the one to remember: every object freed through FreeAndNil had its destructor skipped —
no `inherited`, no child cleanup — because the RTL called FreeMem directly AND `Free` through an
untyped reference cannot dispatch Destroy (the VMT slot is unknown without a class id). It is
now an intrinsic that uses the call site's static type, which is what `obj.Free` already did
correctly.

### The current wall, narrowed (2026-07-13, instrumented)
`AssertEquals('FormatJSON equals JSON', S.AsJSON, S.FormatJSOn)` in `TTestString.TestFormat`
dies with `Expected: ,` at the `.` of `S.AsJSON`. Established by instrumentation, gated on
`CurProc` (NOT on a line number — see below):

- **`S` resolves CORRECTLY**: idx 257, `tyClass`, rec 86 (TJSONString), `skLocal`, block-visible.
  My first read of this — that `S` bound to an unrelated AnsiString `skParam` — was WRONG, and
  the ticket I filed on it is withdrawn: [[bug-pascal-local-var-not-registered-wrong-sym]].
  **The debug print was gated on `CurTok.Line`, and line numbers COLLIDE ACROSS UNITS** — those
  hits were from a different file. Gate instrumentation on `CurProc`, a symbol index, or a token
  SOffset. Never a line number.
- The correct `AssertEquals` overload IS selected (`msg, string, string`; no by-ref params), so
  the arguments are parsed with `ParseExpr`.
- The failure is therefore in the MEMBER ACCESS on a correctly-resolved class variable.
- It is **DECL-ORDER dependent**: moving `TestFormat`'s body to the END of the implementation
  section makes it compile (the wall then moves on to `TTestFloat.DoTest`). Same family as b291,
  where a method's return-type class id was recorded at its BODY rather than its DECLARATION.

Next probe: find why the selector path is not reached for `S.AsJSON` here when the identical
construct compiles standalone (`fj3.pas`: fpcunit + fpjson + the same AssertEquals call). The
answer is something about what is or is not registered at that point in the unit — which is what
"decl-order dependent" means.

### State
The suite's remaining walls are a LONG TAIL, not an architectural blocker. Each one is
CONTEXTUAL — it reproduces green in isolation and only fails inside the real file — so each
needs instrumentation against testjsondata.pp itself, at roughly one compile (~2 min) per
iteration. Current one: line 2062, `by-reference argument must be a variable` in
`TTestFloat.DoTest`, where `Str(F,S)` / `Delete(S,1,1)` / `TestJSONType(J,...)` all compile
fine standalone.

This deserves its own focused session rather than being chased at the tail of a long one. The
method that works (proven repeatedly tonight): do NOT keep writing reproductions — blank the
failing line in a COPY of the real file to walk the wall forward, then instrument the compiler
at the exact dispatch. See [[project_dump_tokens_before_theorising]].

**Rung 2's actual goal — fpjson compiles and produces correct JSON — is DONE.** The suite is a
bonus oracle on top of it.

## What is left in fpjson proper
Only the SCANNER's `\uXXXX` escape path, which builds a UTF-16 surrogate pair. That is a
genuine string-model boundary, not a bug — [[feature-unicodestring-model]]. fpjson's DOM does
not need it.

## Next
Rung 3 — reassess. Likely `rtl-generics` (generic classes x interfaces x class constraints) or
`fcl-xml` DOM.

## Gate
`make test` + self-host byte-identical + cross.
