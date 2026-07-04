# Forward class decl + full decl that adds a base loses the class's fields

- **Type:** bug (compiler — parser / class registration, Track A)
- **Status:** backlog
- **Opened:** 2026-07-04 (found writing TComponent — the `TComponent = class;` +
  `TComponent = class(TPersistent)` pattern)

## Symptom

A forward class declaration `TFoo = class;` followed by a full declaration that
adds a **base class** makes the full class's fields invisible:

```pascal
type
  TBase = class end;
  TFoo = class;                { forward — no base }
  TFooClass = class of TFoo;
  TFoo = class(TBase)          { full — adds a base }
  private
    FVal: Integer;
  public
    constructor Create;
  end;
constructor TFoo.Create;
begin
  FVal := 7;                   { pascal26: error: undefined variable (FVal) }
end;
```

Without the forward decl (declare `TFoo = class(TBase)` directly), it works.
A forward decl whose full form has NO base also works — the trigger is the
forward stub (rootless) + a full decl that introduces inheritance.

## Impact

Blocks the standard `TFoo = class; TFooClass = class of TFoo; TFoo = class(TBase)`
metaclass-before-decl idiom for any inherited class. Worked around in
`lib/rtl/classes.pas` by dropping the forward decl and moving
`TComponentClass = class of TComponent` AFTER the full declaration.

## Direction

The full declaration must attach the base + fields to the SAME class entry the
forward stub created; today the fields appear to land on a different entry (or
the stub's rootless layout wins). Fix the merge of forward stub → full decl when
a base is introduced.

## Acceptance

Repro compiles + runs (FVal=7); regression `.pas`; self-host byte-identical.
