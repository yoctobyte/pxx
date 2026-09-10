---
slug: bug-n-an-ambiguous-property-store-on-a-dynamic-receiver-has-no-setter-path
title: an ambiguous @property STORE on a dynamically-typed receiver is refused, because there is no PyPropertySet
track: N
type: bug
prio: 30
status: open
summary: >
  Two unrelated classes declare a @property of the same name and the receiver is
  a variant: the READ now dispatches at run time through PyPropertyGet, and the
  STORE is still a compile error. The refusal is correct today — pydynattr_set
  writes the side store only, so falling through would silently drop the write —
  but the run-time machinery to lift it is nearly all present already.
---

## What is refused

`test/test_nilpy_variant_property_store_ambiguous_fail.npy` is the shape, and it
is the store half of `test_nilpy_variant_property_read_ambiguous.npy`:

    parts = [Sail(), Mast()]     # both declare @property up, unrelated classes
    for p in parts:
        p.up = True              # error: .up ... is ambiguous

CPython runs this. So it is a real upward-compat gap, not a divergence we chose.

## Why the refusal is right until someone builds the setter path

`PyMakeVariantPropRecv` (compiler/pyparser.inc) cannot pick a class to cast to,
so control falls through to the dynamic-attribute path. On the READ side that is
CPython's own answer — `pydynattr_get` reaches `PyPropertyGet`
(compiler/builtin/pylib.pas:4413), which finds `__prop_get_<name>` in the RTTI of
the class the object ACTUALLY is and CALLS it. On the WRITE side there is no
counterpart: `pydynattr_set` writes the side store and nothing else, so the
setter would never run and the getter would go on answering from the real
backing field. That is exactly
`bug-nilpy-property-setter-is-skipped-on-a-dynamically-typed-receiver` (done/),
which the refusal was added to prevent. A loud error beats a silently dropped
write, so this stays refused until the setter exists.

## The measurement, so nobody has to repeat it

Both halves of the missing piece are already in the tree:

- **The accessor is emitted under a findable name.** `PyPropAccessorPrefix`
  (compiler/pyparser.inc:32162) mangles a `@x.setter` to `__prop_set_<name>`,
  and pyparser.inc:35459 already recognises that prefix. So `PyFindMethByName`
  can reach a setter the same way it reaches a getter.
- **The parameter's KIND is in RTTI.** `TMethInfo.ParamKinds`
  (lib/rtl/typinfo.pas:71) is a block of `Arity` `pxxTk*` words followed by
  `Arity` name pointers. `PyPropertyGet` selects its trampoline off `RetKind`;
  a setter selects off `ParamKinds` word 1 (word 0 is Self).

So `PyPropertySet(obj, name, value): Boolean` looks like a mirror of
`PyPropertyGet` — five trampoline arms (Variant / Int64 / Double / AnsiString /
Boolean), returning False for any kind it does not serve, which keeps today's
behaviour rather than calling through a wrong convention. Then `pydynattr_set`
tries it before writing the store, and the refusal in `PyMakeVariantPropRecv`
can go away for the store half too.

Not done here because it is a run-time change with its own differential test and
its own gate, and the read half is what was blocking a real program.

## Where the refusal lives

`compiler/pyparser.inc`, `PyMakeVariantPropRecv`, the `forStore` arm. Its caller
(the variant member loop) computes `propIsStore` from the lookahead token, which
is the only reason the two halves can differ at all — the field name is
deliberately not consumed before the call.
