---
track: A
prio: 30
type: bug
summary: "Every .bas program compiled for aarch64 or arm32 dies with SIGILL at startup — on HEAD and on `pinned` alike. The BASIC jobs are native-only in the matrix, so nothing was watching."
---

# A BASIC program is an illegal instruction on aarch64 and arm32

- **Type:** bug (Track A — the BASIC driver's target-conditional emission)
- **Status:** done
  [[regression-test-core-test-basic-comprehensive-2]]
- **Owner:** claude-A

## Repro

```
compiler/pascal26 --target=aarch64 test/test_basic_comprehensive.bas /tmp/b64
qemu-aarch64 /tmp/b64
  qemu: uncaught target signal 4 (Illegal instruction) - core dumped
```

Same for `--target=arm32` under `qemu-arm`. Both COMPILE cleanly and die at
runtime, before the first line of output. `--target=i386` is fine (21 lines,
correct). x86-64 is fine.

**Not a regression:** `stable_linux_amd64/default/pinned` produces the same
SIGILL on both targets. This is how BASIC cross-compilation has always been.

## Why nothing caught it

The `.bas` jobs run in the **native** tier only — `tstate` shows
`job_tier/test-core#src:test/test_basic_comprehensive.bas = native` — so no
cross-target verdict has ever been published for this frontend. The failure is
old, silent and complete.

## Where to look first

The BASIC driver open-codes its program prologue, and its entry stub is emitted
as raw x86-64 bytes in at least one place (`EmitB($E9)` + a 32-bit displacement
patch) rather than through `EmitProgramEntryForTarget`, which is the routine
that exists precisely because "every other frontend open-coded the x86-64 one
and nothing else, and a NilPy arm32 binary began with x86-64 bytes" — that
comment is in `pasparser_prog.inc` today, describing the identical bug in a
different frontend.

So the likely shape is: the ELF entry point of a `.bas` binary on aarch64/arm32
contains x86-64 instruction bytes. Check that before anything else — decode the
first bytes at the entry point and compare with a Pascal binary for the same
target.

This is one more instance of the checklist-in-five-copies problem;
[[refactor-a-one-program-driver-prologue-for-every-frontend]] is the systematic
fix, and would likely close this ticket as a side effect.

## Gate

`.bas` tests pass under qemu on aarch64 and arm32, native and i386 unchanged,
self-host byte-identical.

## Fixed 2026-08-24 (claude-A) — and the "where to look first" note was right twice over

All three `.bas` tests now produce byte-identical output on **x86-64, i386,
aarch64 and arm32**. It took two fixes, and the second one is the interesting
half.

### 1. The entry stub, exactly as predicted

The ELF entry point of an aarch64 `.bas` binary held x86-64 bytes:

```
entry=0x4000b0: 48 89 24 25 78 ad 43 00 e9 60 9d 03 00 | 62 00 00 14 ...
                ^--------- x86-64 mov [abs], rsp -----^ ^-- the real aarch64 code
```

`ParseBProgram` open-coded `mov [BSS_INITIAL_RSP], rsp` + `jmp rel32` and
`Patch32(jmpPatch, CodeLen - (jmpPatch + 4))` for every target. Replaced with
`EmitProgramEntryForTarget` / `PatchProgramEntryJump`, which is what that pair
exists for.

**Why BASIC and only BASIC.** Nine drivers open-code this stub — Ada, Erlang,
Fortran, BASIC, Algol, LOLCODE, Whitespace, Rust, Zig. Eight of them refuse a
non-x86-64 target up front (*"only the x86-64 target is supported by the
skeleton"*). BASIC alone had no guard, so it was the one that produced a broken
binary instead of a diagnostic. That is the whole reason this ticket exists and
the others do not.

### 2. A placeholder branch that is inert on x86-64 and destructive everywhere else

With the entry fixed, aarch64 passed all three tests and arm32 passed two —
`test_basic_goto_gosub` ran correctly to the end and then **fell through its
`END`** into the subroutine below and died with *"RETURN without GOSUB"*.
Minimal repro, arm32 only: `10 GOSUB 100 / 20 END / 100 PRINT "sub" / 110
RETURN`.

Found by decoding the emitted words rather than by reading the lowering:

```
0x08048374: EB000000   bl +8      <-- lands at 0x37C, SKIPPING 0x378
0x08048378: E3A070F8   mov r7, #248   (sys_exit_group)
0x0804837c: E3A00000   mov r0, #0
0x08048380: EF000000   svc #0
```

so the `svc` ran with `r7` still holding **4** (write) from the preceding
`PRINT`, and the program did not exit at all.

`EB000000` is `EmitCallProc`'s **forward-reference placeholder**. BASIC's `END`
lowers to a Halt, a Halt calls `__pxx_run_finalizers`, and `bparser` never
called `EmitFinalizerRunnerBody` — the FIFTH step this driver has been caught
missing ([[refactor-a-one-program-driver-prologue-for-every-frontend]]). So the
proc stayed at `BodyAddr = -1` and the call kept its stand-in forever, because
nothing resolves this driver's forward calls: `ApplyCallFixups` is called by six
other drivers and by `DceRun`, and `DceRun` is off unless `--dce` **and**
x86-64 **and** the Pascal frontend.

**The stand-in itself was the bug, and it was a bug on four targets:**

| target | placeholder | what an unpatched one does |
| --- | --- | --- |
| x86-64 | `call rel32=0` | targets the next instruction — falls **through**, inert |
| arm32 | `bl imm=0` | PC reads 8 ahead — **skips an instruction** |
| aarch64 | `bl imm=0` | branches to **itself** — infinite loop (measured: the binary hung) |
| riscv32 | `auipc t0,0; jalr ra,t0,0` | targets the `auipc` — self-loop |
| xtensa | `call0/call8 rel 0` | likewise |

Only x86-64's was harmless, and only x86-64 ever ran these frontends. All five
are now a **NOP** of the same size, so an unpatched call is silently skipped
exactly as it has always been silently skipped on x86-64, and a patched one is
overwritten identically.

`EmitFinalizerRunnerBody` was also added to `bparser` and to the four other
drivers that lacked it (Ada, Fortran, Algol, LOLCODE, Whitespace); every
skeleton frontend's test output is unchanged, verified program by program.

### What was deliberately NOT done

`ApplyCallFixups` is still not called by the BASIC driver. Adding it turns a
unit-free `.bas` program with a string literal into `unresolved forward:
PXXStrFromLit` — a real latent hole, filed as
[[bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits]]. Making the
placeholder inert is what this fix needed; making the pass run is that ticket's
scoping question.

`--target=riscv32` still cannot compile a `.bas` program at all —
`compiler error: PXXWriteNL not found`, identical under `pinned`, so
pre-existing and the same "this driver does not pull the unit" family as the
ticket above.

### Gate

`make compiler/pascal26` fixedpoint converged in one round; `tools/gate.sh
quick` GREEN; the three `.bas` tests wired into `test-core` as CROSS rows on
i386 / aarch64 / arm32 (guarded on qemu-user being present, the same shape
`lib-test`'s cross net block uses); every skeleton frontend's output re-measured
identical.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
