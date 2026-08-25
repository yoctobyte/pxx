---
slug: compat-pascal-strict-fpc-pointer-difference-bytes
title: "--strict-fpc: `typed - untyped` pointer difference counts bytes, as FPC does"
track: P
prio: 15
type: feature
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Re-filed from decide-pointer-difference-unit, decided 2026-08-25 (option 2 + parity behind the flag). The default dialect keeps the uniform element rule; FPC's byte answer for a difference involving an untyped Pointer is a BEHAVIOUR (deterministic, dependable) not a bug, so the dialect contract puts it in the strict family. Ranked 15 deliberately: no corpus target has asked for it."
---

# What to build

Under `--strict-fpc` (and `--mimic-fpc`), `p - q` counts **bytes** when either
operand is an untyped `Pointer`, and elements when both are the same typed
pointer — i.e. use the *smaller* of the two operands' strides, so an untyped
operand (stride 1) forces a byte count. The default dialect is unchanged and
keeps the uniform element rule.

# Why it is owed at all, and why only under the flag

`meta-dialect-extensions-and-fpc-strict` classifies it: *"Behaviour → emulate
under strict. Deterministic and derivable from the source ... Working code can
and does rely on these, so a strict compile must reproduce them even where pxx's
own default is nicer."*

FPC's answer is derivable (`{$TYPEDADDRESS OFF}` makes `@x` a `Pointer`; a
difference with no element type counts bytes), so it is a behaviour, not one of
the bugs strict mode is forbidden to emulate. That makes the strict family its
correct and only home.

# Why prio 15

Per `frontend-compat-philosophy.md`'s corpus rule, *"do not justify core work
with a corpus"* — and here not even a corpus is asking. Nothing depends on this;
it is recorded so the decision is executable if a real FPC port ever needs it,
and ranked so it does not displace work that something depends on.

# Acceptance

```pascal
var a: array[0..7] of Integer; p, p0: ^Integer; u: Pointer;
p0 := @a[0]; p := @a[2]; u := @a[0];
```
Under `--strict-fpc`: `p - p0` = 2, `p - u` = 8, `p - @a[0]` = 8 — matching
`fpc 3.2.2`. Without the flag, all three stay 2. Both polarities tested.
