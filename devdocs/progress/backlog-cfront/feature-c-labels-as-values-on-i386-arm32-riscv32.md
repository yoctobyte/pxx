---
slug: feature-c-labels-as-values-on-i386-arm32-riscv32
track: C
type: feature
prio: 60
status: open
found: 2026-09-02
found-by: frankD
blocked-by: []
summary: "GNU labels-as-values (`&&label`, `goto *expr`) is implemented on x86-64 and aarch64 only; i386, arm32 and riscv32 refuse IR_LABELADDR by name. IT IS THE WHOLE OF `test-lua-cross`, which is RED in seven's newest full tier — measured 2026-09-02 by building lua for all three with `-DLUA_USE_JUMPTABLE=0`: all three then BUILD and run 6/6 under qemu, so nothing else in those ports is missing. The original summary said the three `already build-fail on their variadic ABI` and that `nothing measured is blocked on this`; both are false, and prio has gone 30 -> 60 with the umbrella wired."
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

## Measured: it is the WHOLE blocker, not the first of several (frankZ, 2026-09-02)

Binary `135bb8fec65f1271`, commit `2cf53df52`, `gate.sh quick` GREEN, reseeded
from `stable_linux_amd64/default/pinned` (`converged after 2 round(s)`).

`make test-lua-cross` here reproduces seven's red exactly — aarch64 6/6, and
all three of the others stop on the same node:

```
target i386:    IR op not yet supported: labeladdr
target arm32:   IR op not yet supported: labeladdr
target riscv32: unsupported node in IR codegen: labeladdr
```

**Not a variadic-ABI failure.** Compiling the identical runner with
`-DLUA_USE_JUMPTABLE=0`, which is the one flag that stops lua emitting
`&&label`:

| target | builds | lua suite under qemu |
|---|---|---|
| i386 | yes | 6 pass, 0 fail |
| arm32 | yes | 6 pass, 0 fail |
| riscv32 | yes | 6 pass, 0 fail |

So every other part of the port already works on all three, and `IR_LABELADDR`
plus `IR_JUMP_INDIRECT` is the entire distance between here and a green
`test-lua-cross`.

**Scoping this claim honestly, because the same suite has already fooled
someone once.** frankD established that these six lua programs do NOT
discriminate the two interpreter paths — a `-DLUA_USE_JUMPTABLE=0` build passes
6/6 on x86-64 as well. So the table above is NOT evidence that the jump-table
interpreter works on these targets; it cannot be, since that is precisely the
build it excludes. It is evidence about the REST of the port: that nothing else
is missing behind the node that stops the compile. Whoever implements the node
still owes a run of the real (jump-table) build, and a binary comparison at the
same flags is the control that tells the two apart.

## What it blocks

`test-lua-cross#src:tools/compiler_srchash.sh` — 1 of the 16 jobs red in
seven's full tier at `0f4d2c907d54`. Wired to
[[umbrella-one-full-tier-run-with-no-red-tier]].
