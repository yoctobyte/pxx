---
prio: 65
---

# Unary minus did not apply the integer promotions (silent unsigned compare)

- **Type:** bug (correctness — silent wrong branch)
- **Track:** C — C frontend (`cparser.inc`); tag: compat
- **Status:** done — fixed 2026-07-12, commit bcef62f7.
- **Surfaced by:** tstate `test-c-conformance-aarch64#shard1` — `00200.c`.

## Symptom
`-(unsigned short)1` is the **signed int -1** (the integer promotions apply to the
operand, C11 6.5.3.3p3), not an unsigned 65535. cparser copied the operand's type
onto the AN_NEG node, so the result stayed unsigned and `-(us) < 0` compiled to an
UNSIGNED compare — false for every value.

The arithmetic was never wrong (`-(us)` still printed -1); only the TYPE was. A
silent wrong-branch bug.

c-testsuite `00200.c` (lshift-type.c) detects operand signedness with exactly that
idiom — `(M) < 0 || -(M) < 0` — which is why it failed.

## Fix
Route AN_NEG through the existing `CIntegerPromoteTk`. Unary `~` ALREADY did this
(and carries a comment about the same bug being fixed there once: `~(size_t)0`
dividing as a signed -1); `-` was the sibling that never got it.

int-or-wider unsigned types are correctly NOT promoted — `-(unsigned int)1` stays
unsigned and is never < 0. The regression pins that down so nobody "fixes" it later.

## Regression
`test/cunary_minus_promote_b253.c` (also verified on aarch64 under qemu and i386).

## Gate
make test + self-host byte-identical + `testmgr --tier full` (1199/1199 — this was
the last of the seven open regressions).
