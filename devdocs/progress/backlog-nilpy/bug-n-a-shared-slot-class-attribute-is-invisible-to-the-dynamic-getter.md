---
slug: bug-n-a-shared-slot-class-attribute-is-invisible-to-the-dynamic-getter
title: a class attribute lowered as a shared slot has no instance field, so every dynamic attribute route reports it missing
summary: >
  A class attribute is lowered one of two ways. The copy-at-construction form
  gives the instance a real FIELD, which the reflective getters find through
  the class RTTI. The SHARED SLOT form -- taken when the class is used as a
  value, when something writes the attribute through the class name, or when a
  subclass redeclares it -- gives the instance no field at all, and
  pydynattr_get walks fields, then properties, then __class__, then
  __getattr__, and raises. So hasattr answers False and getattr hands back its
  default for an attribute the STATIC read `self.K` returns correctly. It is
  not about the value's type: measured with `H2 = H` in the file, `K = 7` is
  as invisible as `K = 2 << 20`. The value exists at run time -- pylib's
  PyClsAttrRefGet reads it through a class reference -- so the getter needs a
  route to it, not a new store.
track: N
type: bug
prio: 60
owner: unassigned
status: open
---

## Measured

2026-09-14, at the fix for `bug-n-a-promotable-int-field-is-boxed-as-an-object`.
Three files, one line apart:

| file | lowering | `hasattr(h, "K")` | CPython |
| --- | --- | --- | --- |
| `K = 7` alone | copy-at-construction (a field) | True | True |
| `K = 7` **plus `H2 = H`** | shared slot | **False** | True |
| `K = 2 << 20` **plus `H2 = H`** | shared slot | **False** | True |

`H2 = H` is what makes `PyClassKinUsedAsValueEx` force `caClassW`, in
`compiler/pyparser.inc` (both class-attribute branches call
`PyClsAttrEnsureGlobal` and then skip `AddUField`). `PXXDBG=a.reclayout`
prints no `rec=H` line at all for those two.

## Why it is not the promotable-int ticket

That one was a missing KIND in two boxers, and every route reached the field.
Here there is no field to reach on any route, for any type, and the two
lowerings are a deliberate design decision recorded in
`decide-nilpy-class-attribute-instance-read-model`. The fix is a route from
`pydynattr_get`/`pydynattr_hasattr` to the shared slot, keyed by the
RECEIVER's class -- which is the question `FindClassVar` already answers at
compile time and `PyClsAttrRefGet` already answers at run time for a class
reference.

## Not blocking lekkerzeilen

The demo's wall was the promotable-int one. This was found beside it and is
filed rather than fixed because the route it needs is a design choice about
where the runtime registry lives, not a missing arm.

## The shape to start from

`compiler/builtin/pylib.pas`: `pydynattr_get` (the field/property/__class__/
__getattr__ ladder), `PyClsAttrRefGet` (reads a shared slot given a class
reference), `PyBoxByKind` (shared boxing, now including kinds 27/28).
A positive control must include a LITERAL-valued attribute: the bug is about
the lowering, and a fixture that only tries expression values would pass for
the wrong reason once the promotable-int arms are in.
