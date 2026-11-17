---
slug: feature-c-inline-asm-plus-m-read-write-memory-operand
track: C
prio: 30
type: feature
status: done
created: 2026-11-15
found-by: pxx (Nilix seat), 2026-11-15
tags: [cfront, inline-asm]
blocked-by: []
summary: "gcc accepts a read-write memory operand, e.g. `__asm__ volatile (\"xchgl %0, %1\" : \"=r\"(v), \"+m\"(word) : \"0\"(0u) : \"memory\");`. pxx refuses it (CAsmRefuseUnsupported: 'inline asm read-write constraint \"+m\" is not supported'). This was left refused on purpose in bug-c-inline-asm-refused-plus-r-and-sized-an-array-operand-as-the-array: a memory output has no carrier in this frontend. Second request now, not blocking (Nilix uses its cmpxchg32 helper). The refusal's advice ('write it as an \"=m\" output with an input tied to it') should be checked: if \"=m\" has no carrier either, the advice points at another refusal. The likely shape is the lvalue's address in a register, substituted as `(%reg)` for both directions, since the asm writes the memory itself and nothing needs copying back."
---

# Inline asm "+m"

Reported by the Nilix seat. No user yet beyond that one xchg.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).

## Done 2026-11-17 (x86-64)

`"=m"` and `"+m"` outputs are accepted on x86-64, in CAsmBuildBlock:
- An output that is a plain register-wide local or parameter binds straight to that variable's own frame slot, as an `"m"` input already did.
- Any other lvalue (a dereference, field, subscript, or global) has its address computed before the block into a pool register, and %N becomes `(reg)`.
- Either way the template writes the object itself, so there is no store-back statement. `"+"` therefore costs nothing extra.
- An input tied to a memory output is refused by name (use `"+m"`).
- Other targets still refuse with "not supported on this target".

The refusal advice the ticket questioned is moot now that both forms work.

Test: test/c_inline_asm_memory_outputs.c. It covers xchgl/xchgb on `*p`, `=m` on a field and an array element, and `+m` on `ps->c`, a global, `arr[i]` and a local. The expected output is gcc's; pxx passes at -O0 and -O2 (test-core rows c_asmmemout26 and _o2). It also unblocked rump repro g14b.
