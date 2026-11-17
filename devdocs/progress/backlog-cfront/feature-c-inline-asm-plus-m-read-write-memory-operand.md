---
slug: feature-c-inline-asm-plus-m-read-write-memory-operand
track: C
prio: 30
type: feature
status: backlog
created: 2026-11-15
found-by: pxx (Nilix seat), 2026-11-15
tags: [cfront, inline-asm]
blocked-by: []
summary: "gcc accepts a read-write memory operand, e.g. `__asm__ volatile (\"xchgl %0, %1\" : \"=r\"(v), \"+m\"(word) : \"0\"(0u) : \"memory\");`. pxx refuses it (CAsmRefuseUnsupported: 'inline asm read-write constraint \"+m\" is not supported'). This was left refused on purpose in bug-c-inline-asm-refused-plus-r-and-sized-an-array-operand-as-the-array: a memory output has no carrier in this frontend. Second request now, not blocking (Nilix uses its cmpxchg32 helper). The refusal's advice ('write it as an \"=m\" output with an input tied to it') should be checked: if \"=m\" has no carrier either, the advice points at another refusal. The likely shape is the lvalue's address in a register, substituted as `(%reg)` for both directions, since the asm writes the memory itself and nothing needs copying back."
---

# Inline asm "+m"

Reported by the Nilix seat. No user yet beyond that one xchg.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).
