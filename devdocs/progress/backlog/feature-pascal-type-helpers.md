---
prio: 55
---

# `record helper for T` / `type helper for T` — type helpers

- **Type:** feature (Pascal frontend — Track P; dispatch plumbing may touch shared parser = A gate)
- **Status:** backlog — filed 2026-07-14 during rtl-generics rung-3 recon.
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
