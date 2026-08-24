---
track: A
prio: 60
type: bug
blocked-by: []
status: done
owner: claude-A
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

## Fixed 2026-08-24 (claude-A) — an out-of-bounds write, and reading 1 was right

The ticket offered two readings. **Reading 1 — "a latent out-of-bounds that both
builds commit, and only the pxx build's memory layout turns into an unmapped
address" — is the answer.** Nothing is miscompiled.

### The defect

The -O3 loop-residency pass parks a body's hottest loop scalars in callee-saved
registers. The **pool differs per backend**:

| backend | int pool | size |
| --- | --- | --- |
| x86-64 (`UnifiedResidencyAssign`) | r12..r15 | 4 |
| aarch64 (`UnifiedResidencyAssignA64`) | **x19..x24** | **6** |

Both passes index **one** set of parallel tables — `RcResidentSym`,
`RcResidentReg`, `RcResidentSaveOff` — and those were declared
`array[0..3] of Integer`, sized by x86-64's pool. The aarch64 pass caps the
REGISTER count (`if islot >= 6 then Continue`) and nothing capped the TABLE
index, so residents five and six wrote past the end of all three arrays. They
sit adjacent in BSS, so each overflow landed in the next one.

The aarch64 pass was written as a mirror of the x86-64 one and inherited its
structure; the one thing it deliberately changed — a bigger pool, since aarch64
has no regcall claimants — is the one thing the shared tables encoded.

### Why an EMPTY program, and why the FPC build survived

Both puzzles have the same answer and neither is a coincidence.

**Empty:** the fault is not in the user's program at all. `builtinheap` is
compiled before anything else, and its own routines have four-plus loop-hot
scalars — the backtrace bottoms out in `ParseUsesUnitBody('builtinheap')`. So
the smallest possible program is enough. That is also why
`begin a := 1; WriteLn(a); end` *worked*: nothing about the user's body decides
this, and the apparent non-monotonicity noted in the report above was noise.

**FPC build fine, pxx build dead:** exactly what an out-of-bounds write looks
like. The same store happens in both; only the pxx build's BSS layout puts
something fatal downstream of it. The report called this "the part that decides
how to debug it" and read it as evidence for a miscompile. It was evidence for
neither reading on its own — a layout-sensitive symptom is the *signature* of
reading 1, and treating a build difference as a miscompile signal is the trap.

### How it was actually found

Not by the range-checked seed the report proposed (which still cannot be built —
see below). By reading the aarch64 pass beside its x86-64 twin, noticing the
pool sizes differ while the tables do not, and then **testing that guess instead
of writing it down**: a one-line probe capping `RcResidentCount` at 4 in the
aarch64 pass, rebuilt, crash gone. That is the difference between a plausible
story and a cause (`devdocs/dev/debugging-playbook.md`).

Worth recording that the DWARF backtrace was actively misleading: gdb placed the
fault in `InlineMeasureBody`, a procedure that never runs (its call site is
guarded by `MeasureInline`, off by default). pxx's `-g` output resolves an
address to the nearest preceding function it knows, so a frame inside a
neighbour is attributed to the wrong name. The line that *was* trustworthy is
the one nobody looks at — `ParseUsesUnitBody('builtinheap')`, four frames up,
which said the crash had nothing to do with the input file.

### The fix

`RC_RESIDENT_SLOTS = 6` — the tables are sized by the **largest** pool any
backend assigns from, not by one backend's — and **both** assign loops now test
that bound explicitly rather than relying on their own pool cap to imply it. The
x86-64 loop's existing `>= 4` became `>= RC_RESIDENT_SLOTS`, which cannot admit
more residents there: `islot < nFree` with `nFree <= 4 - (regcall claims)` caps
x86-64 at 4 regardless, and the self-host build is byte-identical, confirming it.

### Gate

`make compiler/pascal26` fixedpoint converged in one round; `tools/gate.sh
quick` GREEN; new `test-core` rows: the empty program compiles at -O3 for
native / i386 / aarch64 / arm32 / riscv32, and
`test/test_o3_residency_six_hot_locals.pas` (six hot locals in one loop, so the
pool actually fills) matches fpc 3.2.2 natively and under qemu on i386 /
aarch64 / arm32. Verified at -O0/-O2/-O3 on all five targets while fixing.

### Left open, deliberately

**The range-checked FPC seed still cannot be built**, and it would have found
this in one run. `fpc -Cr` rejects five `$`-constants in
`ir_codegen_aarch64.inc` and `ir_codegen_arm32.inc` as out of Integer range
while folding them into an Integer parameter (`$E1A00000`, `$EA000000`,
`$BA000000`, `$CA000000`, `$0A000000`). Filed separately rather than fixed here,
because it is a tooling change with its own gate and this ticket had a cause:
[[chore-a-the-range-checked-fpc-seed-cannot-be-built]].

## Log
- 2026-08-24 — resolved, commit a57efd6e2.
