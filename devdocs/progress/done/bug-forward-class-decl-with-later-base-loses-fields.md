# Forward class decl + full decl that adds a base loses the class's fields

- **Type:** bug (compiler — parser / class registration, Track A)
- **Status:** done
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

## Resolution (2026-07-04)

FIXED. Root cause exactly as filed: the full decl called AddUClass again, minting a shadowed duplicate — FindUClass returns the FIRST match, so lookups (incl. the class-of alias) stayed on the empty rootless stub while base+fields went to the invisible second entry. Fix: new UClsForward flag (defs.inc, cleared in AddUClass); bare `class;` without heritage marks the stub; the full decl reuses that entry, re-anchoring UClsFBase/MBase/PBase to the current tails (stub counts are 0) and resetting VirtCount before applying the parent. `class(TBase);` remains the FPC empty-body shorthand. Regression test/test_forward_class_base.pas (6/6: fields, inherited field, is-base, metaclass alias, mutual refs, virtual override through a forward) in test-core. Self-host byte-identical, make test green. lib/rtl/classes.pas workaround (forward dropped, class-of moved after) can revert to the idiom after the next re-pin.
