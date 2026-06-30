# C signed `>>` is a logical (not arithmetic) shift

- **Type:** bug (codegen / C frontend — correctness) — Track A / C
- **Status:** backlog
- **Opened:** 2026-06-30 (found in the open-ticket triage sweep)

## Symptom

In C, `>>` on a **signed** int is an arithmetic shift (sign-extends). pxx gives the
wrong result:

```c
int s = -2;
... (s >> 1) ...     /* C: -1 (arithmetic). pxx returns a value != -1 */
```

So negative signed values shift in zeros (logical) instead of the sign bit. Bites
hashing / fixed-point / any signed-bit-twiddling C code.

## Likely cause

The shift lowering uses a logical right shift (`shr`) regardless of operand
signedness, OR the C frontend doesn't pick the arithmetic-shift IR op for signed
operands. Pascal `shr` is logical by design (unsigned), so the split is: C signed
`>>` must lower to an **arithmetic** right shift (`sar` on x86-64); C unsigned and
Pascal `shr` stay logical. Check whether the IR has an arith-shift op or only `shr`.

## Acceptance

`(-2) >> 1 == -1`, `(-8) >> 2 == -2` for signed C ints across targets; unsigned
`>>` and Pascal `shr` unchanged; test. Relates to
[[feature-c-unsigned-semantics-suite-resweep]].
