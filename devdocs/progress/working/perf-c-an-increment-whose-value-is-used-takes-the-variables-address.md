---
slug: perf-c-an-increment-whose-value-is-used-takes-the-variables-address
track: A
prio: 50
type: perf
status: working
owner: "claude-pxx"
blocked-by: []
summary: "MEASURED 2026-11-20. Rainyday's lib/string.c copy loops, built in userland on x86-64 against gcc -O2: word memcpy 3.5x, memset 4x, and the byte loop `while (n--) *d++ = *s++;` 8.6x. pixx measured the pxx-built kernel at 2.5-4x the gcc-built one on pipes, fork and syscalls (Rainyday 0060). The cause here: `p++` with its value used, and `n -= 32` / `q += 4`, lower through an address temp of the variable (AN_INCDEC / AN_COMPOUND_ASSIGN), so the variable never gets the register path a plain assignment has. At -O2 the same loop in Pascal keeps its pointers in r14/r15; in C it does not."
---

# An increment whose value is used takes the variable's address

The value-unused case was step 3 of
[[feature-xtensa-codegen-density-before-register-allocation]]
(IRLowerForEffect). This is the value-used case, plus compound assignment.

## Change (compiler/ir.inc)

On a plain scalar or pointer variable, under the same test step 3 uses
(not an array, not by-ref, no cell, machine int or pointer, not a promoted
small int):

- `v++` / `v--` with the value used: old := v; v := old + step; yields old.
- `++v` / `--v`: v := v + step; yields v.
- `v OP= rhs` / value-bearing `v = rhs`: v := v OP rhs; yields v. Same binop
  and the same order as the general path.

## Measured (userland, x86-64, busy host so +-15%)

| loop | gcc -O2 | pxx before | pxx after | pxx -O2 before | pxx -O2 after |
|---|---|---|---|---|---|
| byte copy (x0.1) | 0.25-0.29 s | 2.46 | 0.96 | 2.65 | 0.88-1.03 |
| word memcpy 64K x20000 | 0.19-0.20 | 0.70 | 0.57 | 0.55 | 0.53 |
| memset 64K x20000 | 0.07-0.12 | 0.48 | 0.39 | 0.68 | 0.46 |

The byte loop gains 2.5x. The word loops remain about 3x gcc. The rest is
`q[0] = r[0]` indexing and the general stack-machine expression code: register
allocation proper (the toybox ticket's item 3), not this ticket.

## Checked so far

- Self-host converged.
- test/c_incdec_value_on_a_plain_variable.c (new, test-core): same output as
  gcc -O2 at the default level and at -O2, and as the old pxx.
- tools/check_xtensa_density.py OK (loop 36).
- A scratch probe with unsequenced rows: identical to the old pxx at both
  levels.

## Related

- [[feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc]]
- Rainyday docs/tickets/open/0060 (pixx's kernel speed numbers)
