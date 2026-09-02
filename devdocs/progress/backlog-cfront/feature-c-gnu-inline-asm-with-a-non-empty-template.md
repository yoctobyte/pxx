---
slug: feature-c-gnu-inline-asm-with-a-non-empty-template
track: C
type: feature
prio: 40
status: open
found: 2026-09-02
found-by: frankD
blocked-by: []
summary: "pxx's C frontend refuses GNU inline asm whose template is non-empty (`error: C: inline asm with a non-empty template is not supported — the instructions would be silently dropped`). The refusal is right; the gap is real. It is the LAST non-crtl blocker for busybox at 258 applets: networking/tls_sp_c32.c takes an x86-64 asm arm because pxx announces __GNUC__, and its failure takes the 400-object link down with it (curve_P256_compute_pubkey_and_premaster undefined). Everything else in that build now compiles."
---

# GNU inline asm with a non-empty template

```
pascal26:283: error: C: inline asm with a non-empty template is not supported
  in: ./networking/tls_sp_c32.c
```

The refusal itself is the right behaviour and should stay until this lands:
accepting the construct and dropping the instructions is how a program computes
a plausible wrong answer.

## Where it bites, measured 2026-09-02 at 258 applets / 400 translation units

- **networking/tls_sp_c32.c** — the only remaining non-crtl failure in the
  build. Its asm arms are guarded `#if ALLOW_ASM && defined(__GNUC__) &&
  defined(__x86_64__)`, and pxx announces `__GNUC__` (which is also why lua
  takes its computed-goto interpreter here). There IS a portable `#else` arm in
  the file; we do not reach it. **Its failure is also the link failure** —
  `undefined reference to curve_P256_compute_pubkey_and_premaster` is this one
  object missing, not a separate defect.
- **Not** `networking/udhcp/dhcpc.c`, which reported the same error until
  2026-09-02. That one was the HOST's `<asm/swab.h>`
  (`__asm__("bswapl %0" : "=r" (val) : "0" (val))`), reached through
  `<linux/filter.h>`, and is fixed by shadowing that one header with a file
  that defines no `__arch_swab*` so `<linux/swab.h>` takes its own portable
  branch. Worth knowing before this ticket is picked up: **the error names the
  file it was reached FROM, not the file the asm is in**, and that cost one
  wrong diagnosis already.

## Do NOT "fix" this by un-announcing `__GNUC__`

It would make tls_sp_c32.c take its portable arm and would also cost the
computed-goto interpreter in lua, `__attribute__` handling, and every other arm
real C guards that way. The announcement is correct; we do announce a GNU C
dialect. This is a piece of that dialect we have not built.

## Shape of the work

Not a parser change alone. A non-empty template means output/input operand
constraints, clobbers, register allocation that respects them, and emitting the
template's instructions per target. A first useful slice is narrower than that:
a template with only `"r"` / `"m"` operands and a `"memory"` clobber, x86-64
only, with any unsupported constraint keeping today's hard refusal. `barrier()`
(`asm volatile ("":::"memory")`) already works, because an EMPTY template is
accepted.
