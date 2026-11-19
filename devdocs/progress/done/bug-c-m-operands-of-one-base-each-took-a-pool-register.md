---
slug: bug-c-m-operands-of-one-base-each-took-a-pool-register
title: "Inline-asm \"m\" dereferences of one base each took a pool register"
track: C
type: bug
prio: 50
status: done
owner: claude-dupwt
found: 2026-11-19
found-by: rd's test-core sweep (bug-test-core-four-rows-still-red-2026-11-19, casmmpress26)
---

# "m" dereferences of one base each took a pool register

## Before

`test/casm_m_operand_pressure.c` (`msum9`: nine `"m"(v[0..8])` inputs and one
`"=r"` output) was refused: "inline asm needs more registers than this
frontend can pin -- a fixed caller-saved pool of 9". Red since b3c5f711ea,
which made an `"m"` dereference bind the object itself through an address
register (bug-c-an-m-operand-that-is-a-dereference-binds-a-copy): correct,
but one register per operand, and ten operands on nine registers.

## Change

`CAsmMemIdxKey` (cparser.inc) recognises `base[k]` with `base` a plain
identifier, `k` an integer constant and a scalar element whose stride is its
slot size. A later `"m"` input of that shape, with the same base and the same
element type as an earlier one, takes the earlier operand's register and no
carrier of its own; it binds as ATTBIND_MEMREG with its byte distance
(`(k_i - k_lead) * size`) in AttBindOff, which `AsmOpVal` now carries (it
was hard-wired 0). That is `disp(reg)` on x86-64 and `[reg+disp]` through
the i386 text sink, as gcc writes the same block. Any other shape keeps a
register of its own, as before.

## Measured

casmmpress26 matches gcc at -O0 and -O2 (`msum9 72624976668147842`,
`mlocal 42`, `mul32 15`). The 115 lines of inline-asm rows in test-core,
test-c, test-i386 and test-emit-obj pass (casm_goto_fails' i386 half only
because my row extraction dropped its continuation line; it fails the same
way with the old compiler). Gate quick GREEN.
