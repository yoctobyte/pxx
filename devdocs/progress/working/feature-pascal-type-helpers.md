---
prio: 55
---

# `record helper for T` / `type helper for T` — type helpers

- **Type:** feature (Pascal frontend — Track P; dispatch plumbing may touch shared parser = A gate)
- **Status:** working — v1+v2 landed 2026-07-14 (b331); v3 = type-name receivers, rvalue receivers, class helpers
- **Owner:** fable-nightA
- **Blocks:** [[feature-pascal-corpus-generics]] (generics.helpers.pas is in
  Generics.Collections' uses chain), and broadly sysutils.TStringHelper-style
  code across the FPC/Delphi ecosystem.

## Surface needed by generics.helpers (v1 slice)
```pascal
TValueAnsiStringHelper = record helper for AnsiString
  function ToLower: AnsiString; inline;         { Self = the string value }
end;
TValueUInt32Helper = record helper for UInt32
  class function GetSignMask: UInt32; static; inline;
  const SIZED_SIGN_MASK: array[1..32] of UInt32 = (...);
end;
```
Consumers: `ALeft.ToLower` (const string params — lvalue receivers), and
type-name statics `UInt32.GetSignMask` / `UInt32.SIZED_SIGN_MASK[i]` inside
the helpers unit itself.

## Design sketch
1. Type-section parse: `= record|type helper for <type>` → register a class-like
   entry with HelperTargetTk/Rec; members parse via the existing class member
   machinery. Self (param 0) is the TARGET type BY REFERENCE, not tyClass.
2. Impl headers `function THelper.M...` — the Self injection must fork on the
   helper marker (both decl and impl sides must agree, see b321's lesson).
3. Dispatch: member access on a NON-class receiver consults a helper registry
   (target tk+rec → newest helper ci; FPC: last visible helper wins), binds the
   method, passes @receiver as Self. Lvalue receivers first; rvalue receivers
   need a materialized temp (later).
4. Type-name receivers for statics/consts.

## Gate
make test + self-host byte-identical (shared parser); fpjson suite stays green.

## v1 LANDED 2026-07-14 (b331)
Decl (`record helper for <type>` via the advanced-record machinery, helper
marker in UClsHelperTk/Rec), impl-side Self fork, and call dispatch (early
ParseLValueAST intercept → ParseClassRecordSelectors with the helper as rec id;
Self = receiver by reference). Instance methods on variables/params work, incl.
Self mutation and const-string params; last-visible-helper-wins; frozen+managed
strings are one family. Pinned: test/test_record_helper_for_string_b331.pas.

## Remaining (v2+)
- statics + consts INSIDE helpers, and type-name receivers (UInt32.GetSignMask,
  UInt32.SIZED_SIGN_MASK[i]) — generics.helpers' UInt32/UInt64 sections.
- rvalue receivers ('abc'.ToLower, F().ToLower) — need a materialized temp.
- `type helper for` spelling; class helpers.
- generics.defaults then adds the REAL walls: methods NAMED after type keywords
  (class function Integer(constref...)), untyped constref params.

## v2 LANDED (same commit series): helper STATICS + consts
`class function ...; static;` in a helper: Self = target BY VALUE (a dummy —
static bodies may not read Self, per FPC), marked UMthIsStatic, callable both
through a VALUE (c.GetSignMask) and through the HELPER's name
(TU32Helper.GetSignMask — both the record-factory factor path and the
class-name selector path fork on the helper marker and pass a literal-0 Self).
Consts in helper bodies were already global-scoped and work. Remaining:
TARGET-type-name receivers (UInt32.GetSignMask), rvalue receivers, class
helpers — and generics.defaults' methods NAMED after type keywords
(class function Integer(constref ...)), which is the next real wall.
