---
slug: feature-c-labels-as-values-on-i386-arm32-riscv32
track: C
type: feature
prio: 30
status: open
found: 2026-09-02
found-by: frankD
blocked-by: []
summary: "GNU labels-as-values (`&&label`, `goto *expr`) is implemented on x86-64 and aarch64 only. i386, arm32 and riscv32 refuse IR_LABELADDR by name; xtensa and wasm32 cannot compile a C program at all yet, so they are out of scope. Nothing measured is blocked on this — `test-lua-cross`'s other three targets already build-fail on their variadic ABI — so it is a gap worth a number, not a gap worth a session."
---

# Labels-as-values on the remaining 32-bit backends

`6eea46f7c` (x86-64) and its aarch64 follow-up added `AN_LABELADDR` /
`IR_LABELADDR` and `AN_GOTO_INDIRECT` / `IR_JUMP_INDIRECT`. Measured on
`test/c_labels_as_values.c`, 2026-09-02:

```
i386     pascal26:32: error: target i386: IR op not yet supported: labeladdr
arm32    pascal26:32: error: target arm32: IR op not yet supported: labeladdr
riscv32  pascal26:32: error: target riscv32: unsupported node in IR codegen: labeladdr
xtensa   pascal26:5: error: C program entry stub not implemented for this target yet
wasm32   pascal26:5: error: C program entry stub not implemented for this target yet
```

A **named** refusal on each — that is IROpName doing its job, and it is why this
ticket could be written from one command instead of from a backend edit.

## What each one needs

- **arm32 / riscv32** — the same shape as aarch64: a PC-relative
  address-of-label (`adr`-equivalent; riscv `auipc`+`addi`) placed on the
  existing branch fixup list, plus an indirect branch through the value
  register. aarch64's patch loop recognises the placeholder by its top byte;
  each backend's loop needs the same trick with a byte that its other
  placeholders do not use. **Check that byte before copying the pattern** — it
  is the one part that does not transfer.
- **i386** — no PC-relative addressing before x86-64, so an address-of-label is
  either an absolute value patched at finalize (the `IR_PROCADDR` shape, not the
  branch-fixup one) or a `call .+0; pop` thunk. The `IR_PROCADDR` route is the
  one that already exists there; prefer it over inventing a thunk.
- **xtensa / wasm32** — out of scope until a C program links at all. wasm32 has
  no indirect branch to an arbitrary code address in the first place; a computed
  goto there is a `br_table` over a relooped switch, which is a different job.

## Why the priority is low

`test-lua-cross` runs aarch64, arm32, i386 and riscv32; the Makefile's own
comment says the last three "await their variadic-ABI bring-up (they build-fail
early)". So implementing this on them turns one early build failure into a later
one and makes no job green. It becomes real the moment a target's variadic ABI
lands, or the moment a corpus program other than lua wants a computed goto.
