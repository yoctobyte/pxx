---
track: A
prio: 60
type: bug
blocked-by: []
status: backlog
owner: ""
summary: "`pascal26 --target=aarch64 -O3` SEGFAULTS the compiler on `program n; begin end.` — an empty program, no absolute, no loop, nothing. Deterministic, aarch64-only, -O3-only, present on `pinned`. The FPC-seeded build of the SAME source compiles it fine, so it is a miscompile (or a latent out-of-bounds) in the self-hosted binary, not a logic error visible to FPC."
---

# `--target=aarch64 -O3` segfaults the compiler on an empty program

Found 2026-08-24 while cross-checking an unrelated fix across targets and
`-O` levels — the fix's test compiled everywhere except this one cell.

## Measured

```
$ printf 'program n; begin end.\n' > e.pas
$ compiler/pascal26 --target=aarch64 -O3 e.pas eo
Segmentation fault
```

Deterministic — three runs, three faults, same address.

| | rc |
| --- | --- |
| `--target=aarch64 -O2` | 0 |
| `--target=aarch64 -O3` | **139** |
| `--target=arm32 -O3` | 0 |
| `--target=i386 -O3` | 0 |
| `--target=riscv32 -O3` | 0 |
| native x86-64 `-O3` | 0 |

So: **aarch64 only, -O3 only.** Present on `pinned` as well as HEAD, so it is
not a regression from anything landed today.

It is not "no program compiles": `program n; var a: Integer; begin a := 1;
WriteLn(a); end.` compiles clean at aarch64 -O3, while the empty program and
`begin a := 1; end` both fault. That non-monotonicity — a BIGGER program working
where a smaller one dies — is the tell for an out-of-bounds rather than a missing
case, since a missing case would fail on the superset too.

## The fault

```
Program received signal SIGSEGV
=> 0x922af0:  mov %ecx,(%rax)
rax  0x800000000048        <-- the store's destination
rcx  0x6
rdx  0xffffffffffffffff
rdi  0xffffffffffffffff
```

A 4-byte store of `6` through `0x8000_0000_0048` — `(1 shl 47) + $48`, not a
plausible heap or BSS address, with two registers holding `-1` beside it. That
is a computed base, not a null deref: something indexed a table with a value it
should have rejected (the two `-1`s are the obvious suspects) or scaled an index
into a nonsense address.

## The part that decides how to debug it

**The FPC-seeded build of the same source does NOT fault.**

```
$ fpc -O1 -g -gl -Tlinux -Px86_64 -opxx-dbg compiler/compiler.pas
$ PXX_HOME=<repo> ./pxx-dbg --target=aarch64 -O3 e.pas eo
ok: eo  [code=159144B  data=1872B  bss=42316B  procs=128]
```

Same source, same input, same flags — the pxx-built compiler dies and the
FPC-built one succeeds. Two readings, and they need different fixes:

1. **A latent out-of-bounds** that both builds commit, and only the pxx build's
   memory layout turns into an unmapped address. Most likely, and it means the
   defect is ordinary compiler logic that FPC's layout happens to forgive.
2. **A miscompile** — the self-hosted binary computes something the FPC one does
   not. Rarer, and much more serious, since it would mean this code path is
   compiled wrong.

Distinguishing them is the first step and it is cheap: build the FPC seed with
range checking and run it again. Note that plain `-Cr` does not compile today —
`fpc -Cr` rejects five `$`-constants in `ir_codegen_aarch64.inc` and
`ir_codegen_arm32.inc` as out of Integer range while folding, so the checked
build needs those five sites written as signed constants first (worth doing on
its own: a range-checked seed is a debugging tool this repo currently cannot
build). If the checked seed reports an index, reading 1 is confirmed and the
site is named. If it runs clean, reading 2 is live.

## Why this is prio 60 and not a corner

`-O3` is the tier every new optimization pass lands in before promotion, and
aarch64 is one of the two backends per-backend optimization effort targets
(CLAUDE.md, Track O). A backend that cannot compile an empty program at the tier
where new passes are developed means aarch64 `-O3` is untested ground — and the
crash is in the COMPILER, so nothing downstream ever gets a chance to be wrong.

## Gate

`compiler/pascal26 --target=aarch64 -O3` compiles the empty program, the
`a := 1` program and `test/test_absolute_alias_survives_residency.pas` (which is
where this was found — its Makefile row deliberately skips aarch64 -O3 today and
should stop skipping when this closes). Plus Track A's own gate.
