---
track: U
prio: 60
type: decide
---

# Decide: what should NilPy do when an operator gets operand types Python rejects?

CPython raises `TypeError` for `3 - "ab"`, `2.5 * "ab"`, `3 < [1, 2]`. NilPy
currently does pointer arithmetic on the handle and returns a plausible wrong
number, hangs, or segfaults, depending on the operator
([[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]],
[[bug-nilpy-float-times-string-hangs]],
[[bug-nilpy-int-equals-string-segfaults]]). The individual crashes and hangs
are plain bugs and are filed as such. What needs a decision is the POLICY the
fixes should implement, because it applies to every operator and every builtin,
not just the ones the sweep happened to reach.

## The fork

1. **Static rejection only.** Compile-time error when both operand types are
   statically known and the pair is meaningless. No runtime cost; catches the
   literal and annotated cases; silent on anything variant-typed.
2. **Dynamic raise.** The variant arithmetic helpers raise a catchable NilPy
   exception when the tags do not admit the operator. Complete; costs a tag
   check on the dynamic path (those helpers already switch on the tag, so it is
   close to free where it matters). Needs the exception to be a real NilPy
   exception, not a Pascal runtime trap — the same requirement as
   [[bug-nilpy-division-by-zero-is-not-catchable]].
3. **Define it away.** Give the operators a total semantics (None as 0,
   handle-as-number, etc.) and document the divergence. Rejected as written:
   a result derived from a heap address is not a semantics, it is a different
   answer on every run.

## Recommendation

1 and 2 together. 1 is small and immediately valuable; 2 closes the dynamic
hole and shares the machinery division-by-zero needs anyway. That also settles
the wider question — NilPy gets real `TypeError`-shaped runtime errors — which
is why this is a decision and not just a bug fix.

## Why it is a Track U item

It sets NilPy's stance on type errors in general (builtins, indexing, attribute
access, not just arithmetic), and it trades strictness against the deliberately
lax dialect posture. That is a direction call, not something to infer from the
code.
