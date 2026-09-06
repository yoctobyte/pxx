---
slug: compat-p-at-over-a-method-pointer-field-yields-the-fields-address-not-the-methods
title: "`@o.Ev` where `Ev` is a method-pointer FIELD yields the field's address; FPC's Delphi mode yields the method's"
track: P
prio: 30
type: compat
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
blocked-by: []
summary: "MEASURED 2026-09-06 at f60ee1bd4, compiler 182dd5cad3f2, and on pin v404, so it is PRE-EXISTING and independent of the selector-walk fix it was found beside. For `Ev: TNotify` (a `procedure(S: TObject) of object` FIELD) with Ev never assigned, `pp := @o.Ev; WriteLn(pp = nil)` prints FALSE under pxx and TRUE under fpc 3.2.2 -Mdelphi: pxx takes the ADDRESS OF THE FIELD (never nil), fpc's Delphi mode reads the procedural variable's VALUE (nil). Same answer for a typed `^TNotify` target. IT IS AT ONE DOT, so it is not about the selector walk: `@o.Ev` alone diverges, and the multi-selector spellings `@o.R.Ev` and `@o.Items[0].Ev` diverge for the same reason once they parse at all (they were refused before f60ee1bd4 / the property-face commit). NOT ESTABLISHED: which spelling real code wants. Delphi's rule is that `@procvar` is the value and `@@procvar` is the address, so matching FPC changes what `@o.Ev` means for every existing user of that spelling in this tree, and that population has NOT been counted -- that census is the first step and it is why this is filed rather than fixed."
---

# `@` over a method-pointer field: address or value?

Found while fixing
[[bug-p-at-over-a-class-base-consumes-only-one-selector]], by a probe that
used a method-pointer field as the chain's last member and so measured two
things at once. The selector-walk defect is fixed; this is what was underneath.

## The measurement

```pascal
type TNotify = procedure(S: TObject) of object;
     TOwner = class public Ev: TNotify; end;
var o: TOwner; pp: Pointer;
begin
  o := TOwner.Create;             { Ev is never assigned }
  pp := @o.Ev;  WriteLn(pp = nil);
end.
```

| compiler | answer | reading |
| --- | --- | --- |
| pxx at `182dd5cad3f2` | `FALSE` | `@` took the FIELD's address |
| pxx at **pin v404** | `FALSE` | pre-existing, not from this week |
| fpc 3.2.2 `-Mdelphi` | `TRUE` | `@` read the procedural variable's VALUE, which is nil |

A typed `pe: ^TNotify` target answers identically, so it is not about the
result type either.

## Why it is filed and not fixed

**Delphi's rule is that `@procvar` is the VALUE and `@@procvar` is the
address.** Adopting it is a one-line change in intent and a behaviour change for
every existing use of `@<procedural-field>` in this tree — and that population
has not been counted. `lib/pcl`'s event wiring and anything doing
`p := @obj.OnSomething` would silently change meaning rather than fail to
compile, which is the worst shape a compat change can have.

**So the first step is the census, not the fix:** how many sites take `@` of a
procedural-typed field or variable, and what do they do with the result.

Also unmeasured, and it decides how much this matters: whether `@@` is accepted
at all today. If it is not, there is currently no spelling for "the address of
this method pointer", and adopting FPC's rule would remove the only one.

## What it is NOT

Not the selector walk. `@o.Ev` is ONE dot and diverges on its own; the
multi-selector spellings inherit it rather than cause it. And not a defect in
the fix that found it — `test_at_over_a_class_base_walks_every_selector`
deliberately ends every chain in a DATA field for exactly this reason, so its
rows measure the walk and nothing else.
