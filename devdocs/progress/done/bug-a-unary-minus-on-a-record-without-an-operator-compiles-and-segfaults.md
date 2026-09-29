---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankd-90 (ucomplex `w := -z`, vecmath `-a` on a TVec3), via frankuser
tags: [pascal, operator, record, accepts-invalid, segfault]
summary: "`b := -a` on a record with no unary `operator -` compiled into an integer negation of the aggregate (AN_NEG) and segfaulted at run time, on v441, v451 and tip. fpc 3.2.2 refuses it with `Operator is not overloaded: - \"R\"`. ParseFactor's tkMinus arm now gives that refusal for a record or class operand when UnaryOpOverloadCall finds nothing (Pascal only). pxx's ucomplex lacked the unary minus that fpc's declares, which is how users hit this, so it gains one. vecmath (pxx's own unit) has none and now gets fpc's refusal instead of a crash."
owner: ""
---

# Unary minus on a record without an operator compiles and segfaults

```pascal
type R = record x, y: Double; end;
var a, b: R;
b := -a;      { fpc: Error: Operator is not overloaded: - "R"   pxx: rc 0, then SIGSEGV }
```

## Fix

In ParseFactor's tkMinus arm, after UnaryOpOverloadCall declines, a
tyRecord/tyClass operand is refused with fpc's message (the UCls name when
there is one). Nil Python is excluded, since its `-obj` never reaches this
AN_NEG.

lib/rtl/ucomplex.pas gains `operator - (z1: complex) z: complex`, which fpc's
ucomplex declares (packages/rtl-extra/src/inc/ucomplex.pp:151). The pinned
compiler builds the new unit.

lib/rtl/vecmath.pas has no unary minus for its vectors. It is pxx's own unit,
so adding one is a feature and not parity; `-v` is now a compile error there
rather than a crash.

## Tests

- test_unary_minus_on_a_record_with_an_operator: a global `operator -`, an
  advanced record's `class operator -`, ucomplex's `-z`, and `a <> -a` /
  `a = -(-a)` on both. Its expected output is fpc 3.2.2's; it passes on six
  targets.
- test_unary_minus_on_a_record_needs_an_operator: the refusal row, with fpc's
  exact message.
