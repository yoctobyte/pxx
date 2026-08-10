---
track: A
prio: 40
type: bug
blocked-by: []
---

# A metaclass returned from a FUNCTION is not a receiver

- **Type:** bug (wrong refusal, with an internal-sounding message) — **Track A**
- **Split from** [[bug-a-a-metaclass-typed-record-field-is-not-a-receiver]],
  which fixed the FIELD spelling of the same family.
- **Pre-existing.**

```pascal
type TBaseClass = class of TBase;
function Give: TBaseClass; begin Result := TDer; end;
begin WriteLn(Give.Kind); end.
```

FPC prints `der`. pxx:

    IR_UNSUPPORTED: frontend could not lower AST node (kind 8) — a frontend gap,
    would miscompile

## Why it is a different fix from the field one

The field case lives in `ParseLValueAST`'s metaclass-receiver list. A CALL
result does not reach that list at all: `ApplyCallResultPtrSuffix` sees a
typed-pointer return (`ProcRetPtrElemTk` = `tyClass`) and walks `^` / `[i]` /
`.field` over it with the record-field builder — so `.Kind`, a class METHOD,
becomes an `AN_FIELD`, which lowering then cannot handle. Hence the internal
message rather than a diagnostic.

The fix is to notice, in `ApplyCallResultPtrSuffix`, that the pointee is a
CLASS and hand off to the metaclass machinery (`ci` = `ProcRetPtrElemRec` -
`REC_UCLASS_BASE`) instead of the field walker — the same handoff the other
three base kinds already make.

**Do not add a fifth ad-hoc arm without looking at the whole family first.**
Four sites now decide "is this a metaclass value?" by base node kind
(`AN_IDENT`, `AN_PTR_CAST`, `AN_INDEX`, `AN_FIELD`), plus this one in a
different function. One predicate — `NodeMetaclassCi(node): Integer` — would
replace all of them and is very likely the smaller change; see
[[project_record_field_and_selector_resolution_landmines]] and
`devdocs/dev/normalise-dont-special-case.md`.

## Gate

`Give.Kind`, `Give.ClassName` and `Give.Create` matching FPC, the four existing
spellings still green (`test/test_metaclass_field_receiver.pas`), self-host
byte-identical.
