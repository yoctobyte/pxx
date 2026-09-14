---
slug: bug-n-a-promotable-int-field-is-boxed-as-an-object
title: a class attribute from an arithmetic expression is typed tyPromoInt64, and neither reflective boxer had an arm for it
summary: >
  `SLICE = 2 << 20` at class level is retyped tyPromoInt64 (a single literal
  stays tyInt64), and the two reflective field boxers both end in an
  "anything else" arm. pylib's PyBoxByKind reported NOT FOUND, so hasattr
  answered False and getattr handed back its default for an attribute the
  STATIC read returns correctly. pyeval's arm is worse: it treats an unknown
  kind as a class pointer, so it read the promo slot's TAG as an object
  address, PXXObjRetain'd it, and handed back a plausible object -- which
  surfaced four frames away as `TypeError: expected a number, got object`
  inside an interpreted lambda, and could fault on the retain. Fixed by adding
  kinds 27/28 to both boxers via PXXPromoToVariant. Fixture
  test_nilpy_a_class_attribute_from_an_expression_is_readable_dynamically.
track: N
type: bug
prio: 90
owner: frank-user
status: done
---

## What it was

Two sites, one cause, and the cause is a new TypeKind meeting two old
`else` arms.

`compiler/builtin/pylib.pas`, `PyBoxByKind` -- shared by `PyDeclaredAttrGet`
and `PyClsAttrRefGet`, and its own header says a second copy of it is how one
kind ends up supported on one route and silently wrong on the other. It has
arms for 23/19/18/2/3/13/14/1/11/12/9/10/7/8/15/16/22/6 and nothing else, and
its `else` sets `found := False` -- deliberately, because answering with
SOMETHING would be a wrong value. Correct policy, wrong outcome here: the
attribute plainly exists.

`compiler/builtin/pyeval.pas`, the `case kind of` after `GetFieldPtr`. Its
`else` assumes a class or aggregate field and does

    r^.VType := 7; r^.Payload := PInt64(p)^;
    PXXObjRetain(Pointer(NativeInt(r^.Payload)));

For a promotable int that reads the slot's TAG word as an object pointer and
retains it. Nothing raises. The value travels as an object until something
asks it for a number.

## How it presented

lekkerzeilen, `app.py:1709` `SLICE = 2 << 20`, read at `app.py:1756` from
inside `lambda g, f, t, p, i=want, o=at, d=data:
stage[name].fill(i, o, d[o:o + self.SLICE])`. The lambda is interpreted by
pyeval, so the read took the second arm above, and the failure appeared as

    Unhandled exception: TypeError: expected a number, got object

raised from `pyvar_to_int` under `pyadd_v` -- with every capture correct
(`o=int`, `self=object class=App`) and nothing in the message naming an
attribute, a class, or a line. Outside `setarch -R` the process died silently
at 139 instead; ASLR, not threads, decided which (measured by lekkerzeilen-c8).

## Why only the expression spelling

The class-attribute retype asks `PyInferExprType`. A bare literal is tyInt64
and took the existing arm 13, so `K = 7` was right and `K = 2 << 20` was not,
two characters apart. Measured, same class, one run:

| initialiser | kind | hasattr before | after |
| --- | --- | --- | --- |
| `LIT = 7` | tyInt64 (13) | True | True |
| `NEG = -3` | tyInt64 (13) | True | True |
| `STR = "a" + "b"` | tyAnsiString (23) | True | True |
| `LST = [1, 2]` | tyClass (6) | True | True |
| `DCT = {7: [3]}` | tyClass (6) | True | True |
| `CALL = dict()` | tyClass (6) | True | True |
| `EXPR = 2 << 20` | **tyPromoInt64 (28)** | **False** | True |
| `SUM = 2 + 5` | **tyPromoInt64 (28)** | **False** | True |

## The residual, and it is a SEPARATE ticket

A class attribute lowered as a SHARED SLOT -- which happens when the class is
used as a value, written through the class name, or redeclared in the chain --
has no instance field at all, so no field boxer can reach it. Measured at this
fix: with `H2 = H` present, `hasattr(h, "K")` is False for `K = 7` as well as
for `K = 2 << 20`. That is a wider gap, it is not what lekkerzeilen hit, and
it is filed as
`bug-n-a-shared-slot-class-attribute-is-invisible-to-the-dynamic-getter`.

## Guard

`test_nilpy_a_class_attribute_from_an_expression_is_readable_dynamically`,
three routes (static read, computed-name reflective read, read from inside an
interpreted closure) plus arithmetic on the result, because the old pyeval arm
handed back something that only failed once a number was asked of it. The
literal rows are the positive control. Reverted, the fixture is rc=139 with
three wrong rows; with the fix it matches CPython exactly.

## Log
- 2026-09-14 — resolved, commit 900d446e9.
