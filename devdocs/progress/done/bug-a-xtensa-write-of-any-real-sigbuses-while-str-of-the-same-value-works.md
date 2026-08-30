---
track: A+S
type: bug
prio: 45
status: done
blocked-by: []
found: 2026-08-30
found-by: frankS
owner: frankS
---

<!-- UN-BLOCKED 2026-08-30, coordinator. Its only blocker
`bug-a-a-hidden-aggregate-result-temp-gets-an-unaligned-frame-slot` is CLOSED
(frankC, one line flooring alignment in the allocator), so this sat in `blocked/`
with nothing blocking it -- and `ready`/`next` never scan `blocked/`, which makes
that state invisible to the ranker rather than merely untidy. Flagged by frankB
via `progress.sh check`'s STALE-EDGE-HIDDEN.

MOVED TO `backlog/`, NOT RESOLVED. frankS measured `test_write_real_frame_align`,
`test_cross_float_return` and `test_single_in_aggregate` all MATCHING after that
fix, which strongly suggests the SIGBUS is gone -- but "the blocker is in done/"
and "the capability works" are different claims, and closing this on someone
else's adjacent measurement is exactly the filing-decision-as-measurement error
this board keeps recording. The S lane has hosted xtensa running and can settle it
in one run.

RETIREMENT TEST: run this ticket's own repro at HEAD. If `Write` of a real no
longer SIGBUSes, resolve it -- and note that a residual DIFFERENCE is NOT this
bug: frankC filed
`bug-a-write-picks-a-different-float-width-per-target-and-both-disagree-with-fpc`
for the width divergence that survived the alignment fix. Do not let this ticket
absorb that one; they have different causes and different lanes of evidence. -->

# `Write` of any real SIGBUSes on xtensa — while `Str` of the same value is correct

`WriteLn(d)` where `d` is a `Double`, a `Single`, or a float literal faults with
SIGBUS on hosted xtensa. Every other thing you can do with that value works.

## Repro

`--target=xtensa --platform=posix --xtensa-soft-mulhigh`, Call0, qemu-xtensa.

```pascal
program t; var d: Double;
begin d := 7; WriteLn('A'); WriteLn('B ', d); WriteLn('C'); end.
{ x86-64: A / B  7.0000000000000000E+000 / C
  xtensa: A / B  <SIGBUS> }
```

Same fault for `WriteLn(d:0:2)`, for a `Single`, and for a bare literal
`WriteLn(7.5:0:2)`. It faults *after* emitting the leading string argument, so
the first part of the line reaches stdout and the process dies mid-`WriteLn`.

## What still works — this is the whole diagnostic value of the ticket

Measured against the x86-64 oracle, all identical, all on the same binary that
faults above:

| | xtensa | oracle |
| --- | --- | --- |
| the value's raw bits (`p := @d; p^` as Int64) | `hi=1075576832 lo=0` | same |
| passing it by value to a user proc, bits read inside | `hi=1075576832 lo=0` | same |
| float arithmetic (`Trunc(d * 2)`) | `14` | same |
| **`Str(d:0:2, s)`, then `WriteLn(s)`** | **`[7.00]`** | same |

So the value model is right, the ABI for a by-value real is right, float
arithmetic is right, and **the float-to-decimal conversion itself is right** —
`Str` produces the correct characters. Only the `Write`/`WriteLn` path for a
real argument faults. Look at how the compiler marshals a real into the write
runtime, not at the conversion or the value model.

## Not Track F

Per `CLAUDE.md`'s F charter: **a crash is not F.** "Rank the mechanism, never
the datatype" — the subject here is a faulting argument-marshalling path that
happens to carry a float, not the accuracy or the formatting of a rendered
value. `Str` already renders it correctly, which is the direct evidence that
rendering is not the defect. Ordinary A+S bug at ordinary priority.

## Scope

Blocks `test_cross_float`, `test_cross_float_return` and
`test_single_in_aggregate` — three of the 13 remaining divergences in
[[bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs]] — and it
masks anything else float-shaped, because the natural probe for a float defect
is to print the float. It cost a wrong first diagnosis tonight: the probe for
the missing `IR_STORE_MEM` float branch faulted here instead, and that branch
had to be measured by reading raw bits back as an `Int64` and by ablation.

## Bound

Object-level plus observable output, hosted profile, Call0,
`--xtensa-soft-mulhigh`, binary `4c878d2df324`, against x86-64 built from the
same source. Windowed not checked. Not checked on real or emulated ESP silicon.

---

## ROOT CAUSE FOUND — and it is not in the write path at all. frankS, 2026-08-30

Traced with tools this box was believed not to have: the ESP-IDF toolchain ships
`xtensa-esp-elf-objdump` (and a gdb, and a riscv32 pair) under
`~/.espressif/tools/**`, off `PATH` until `export.sh` is sourced. I had recorded
earlier the same night that there was no xtensa disassembler here. There is.

`qemu-xtensa -strace` gives the shape immediately:

```
write(1,0x807d598,2)B  = 2
write(1,0x207ffb9f,1)  = 1
--- SIGBUS {si_signo=SIGBUS, si_code=1, si_addr=0x207ff537} ---
```

**`si_code=1` is `BUS_ADRALN`** and `0x207ff537` is an ODD address. Not a wild
pointer — a misaligned one. `qemu-xtensa -d in_asm` names the block, and
`--debug` (which prints `proc N: NAME at OFFSET`) names the routine:
**`PxxSciDigits17`**, 45 bytes in, still in its prologue:

```
08074264: movi a8, -1649
08074267: add  a8, a15, a8
0807426a: movi a9, 0
0807426d: s32i a9, a8, 0     <-- a15 - 1649 is odd
```

That is the **hidden-aggregate-temp nil-init**, and the slot it writes has an
odd frame offset. Filed as
[[bug-a-a-hidden-aggregate-result-temp-gets-an-unaligned-frame-slot]], with the
eight offending slots read out of the compiler's own symbol table and the
riscv32 disassembly showing **identical offsets** — so it is shared layout in
`ir.inc`/`symtab.inc`, not xtensa codegen, and xtensa is only the target that
traps it.

`Str(d:0:2, s)` is correct because it reaches the same formatting code from a
call site whose frame does not carry those temps. Nothing about the write path
was ever wrong.

**Blocked, not fixed:** `ir.inc` and `symtab.inc` are a Track S stop-line. The
fix is one line in Track A's files and belongs to A.

## Log

- 2026-08-30 — **RETIREMENT TEST RUN, and it passes. Resolved.** The ticket's own
  repro, verbatim, `--target=xtensa --platform=posix --xtensa-soft-mulhigh`,
  Call0, qemu-xtensa:

  ```
  A
  B  7.0000000000000000E+000
  C
  ```

  Identical to the x86-64 oracle. No SIGBUS.
- 2026-08-30 — resolved, commit PENDING-COMMIT.

### It is NOT an instance of the data-section alignment defect — checked, not assumed

This was re-tested during a sweep of every open xtensa SIGBUS ticket against the
two builds that bracket
[[bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why]],
because a `Write` of a real faulting while `Str` of the same value works is a
difference in what gets DEREFERENCED, which is that defect's signature.

It is not. The repro passes at **`75d2ba662^` as well as at `75d2ba662` and at
HEAD** — so it was already fixed before the data-section alignment changed, by
`bug-a-a-hidden-aggregate-result-temp-gets-an-unaligned-frame-slot` (frankC's
allocator alignment floor), exactly as the un-blocking note predicted. Two
alignment defects, one in the FRAME and one in the DATA SECTION, with the same
symptom on the same target; this ticket belongs to the first.

Resolving on this ticket's own repro rather than on the adjacent measurements
that made it look fixed, which is what the retirement note asked for.

### Not absorbed

The float-width divergence remains
`bug-a-write-picks-a-different-float-width-per-target-and-both-disagree-with-fpc`.
Different cause, different evidence, still open.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
