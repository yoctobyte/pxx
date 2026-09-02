---
slug: feature-c-labels-as-values-on-i386-arm32-riscv32
track: C
type: feature
prio: 60
status: done
found: 2026-09-02
found-by: frankD
blocked-by: []
summary: "DONE 2026-09-02: GNU labels-as-values (`&&label`, `goto *expr`) now works on i386, arm32 and riscv32 as well as x86-64 and aarch64, and `test-lua-cross` is GREEN on all four targets (24/24) with the jump-table interpreter — proven live by binary identity against `-DLUA_USE_JUMPTABLE=1`, with the `=0` build as the positive control. arm32 uses an inline literal word plus `add r0,pc`; riscv32 uses `auipc`/`addi` through the existing `RISCVPcrelSplit`; i386 uses a `call .+5`/`pop eax`/`add eax,imm32` thunk rather than the absolute `IR_PROCADDR` shape this ticket originally recommended, because an absolute address needs a relocation under `--emit-obj`."
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

## Done — all three, and `test-lua-cross` is 24/24 (frankD, 2026-09-02)

Binary `5df66928aa39`, `converged after 1 round(s)`.

`make test-lua-cross` now passes every script on every target in
`LUA_CROSS_TARGETS`: aarch64, arm32, i386, riscv32 — 6 each, 0 fail, 0 skip.
`test/c_labels_as_values.c` prints gcc's eight lines under all three new
targets and is wired as a row in `test-i386`, `test-arm32` and `test-riscv32`.

**The residual question this ticket left open is closed.** frankZ's table was
scoped honestly to "nothing ELSE in the port is missing", because the six lua
scripts do not discriminate the two interpreter paths and the `=0` build was
the one measured. The control that does discriminate is binary identity at the
same flags, and it was run on the two targets whose encodings are new work:

| target | default vs `-DLUA_USE_JUMPTABLE=1` | default vs `-DLUA_USE_JUMPTABLE=0` |
|---|---|---|
| i386 | identical | differs |
| riscv32 | identical | differs |

So the binary that passed 6/6 IS the jump-table binary, and the `=0` row is the
positive control proving the flag reaches the code at all — without it,
"identical" would also be what a flag that does nothing produces.

A second, independent control comes free from the failure this ticket
describes: `IR op not yet supported: labeladdr` can only be raised by a source
that emits `&&label`. The same runner that raised it now builds. Two readings
that fail differently.

### What each backend got

- **arm32** — `ldr r0,[pc,#0]` / `b .+8` / `.word delta` / `add r0,pc,r0`.
  No arm32 immediate form reaches an arbitrary label, so the delta travels in
  an inline literal word that the branch steps over.
- **riscv32** — `auipc a0` / `addi a0,a0,lo`, split by the existing
  `RISCVPcrelSplit` (`compiler/rv32enc.inc:136`), which is the same helper the
  `auipc`/`jalr` long jump 400 lines above already uses. The first draft
  re-derived the hi/lo split by hand and was wrong about the borrow that a
  sign-extended low half forces; the helper is the one place that rule is
  written.
- **i386** — `call .+5` / `pop eax` / `add eax,imm32`.

**The i386 route deliberately diverges from this ticket's own advice**, which
said to prefer the existing absolute `IR_PROCADDR` shape over "inventing a
thunk". That advice was written before the position-dependence work: an
absolute address patched at finalize is exactly what
`feature-a-x86-64-object-output-is-position-dependent` exists to remove, and
`--emit-obj` on i386 would need a relocation for every `&&label`. The thunk
needs none and costs two bytes plus a stack round-trip once per label
reference, not per dispatch. The advice was reasonable and is now stale; it is
left above rather than edited, since the reasoning is the point.

Its fixup base is the one thing that does not transfer from the other four
backends: every other patch site is `target - (pos+4)`, but here the value in
`eax` is the address the `call` pushed, which sits at `pos-2`. The first
version used `pos-1` and segfaulted under qemu on the first dispatch — caught
because the eight-row test runs, not because anything looked wrong.

xtensa and wasm32 remain out of scope for the reason stated above: no C
program links on them yet, and wasm32 has no indirect branch to an arbitrary
code address at all.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
