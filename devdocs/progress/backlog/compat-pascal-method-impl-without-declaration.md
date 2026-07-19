---
prio: 20
type: compat
---

# `TC.Foo` implementation for a method the class never DECLARED compiles (FPC rejects)

- **Track:** P (Pascal frontend; shared parser — A's gate). compat tag.
- Found while fixing bug-pascal-undefined-field-on-empty-record-compiles
  (4d46a7ad); NOT silent-wrong-value — the registered method works and
  dispatches consistently, so this is a parity diagnostic, not a bug promo.

## Repro

```pascal
type
  TC0 = class
  end;
function TC0.Calc: longint;
begin
  Calc := 7;
end;
```

pxx: compiles, `c.Calc` returns 7. FPC: error (method not declared in class).

## Where

parser.inc ~22522: the method-impl binder's not-found branch deliberately
falls back to `AddUMeth` ("falling back to the name match for a
not-yet-declared method"). Behind a strict flag per the strict-* policy
(--strict-fpc umbrella), NOT default — the lax registration may be relied on.
Related: bug-pascal-overload-impl-decl-signature-match.
