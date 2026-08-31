---
slug: bug-a-no-cross-target-can-build-the-compiler-itself
track: A
prio: 60
type: bug
status: working
owner: frankS
blocked-by: []
summary: "PARTLY FIXED; re-measured 2026-08-31 by frankA at fixedpoint 7dd26baa7a80 and it was STALE: both causes it named as remaining are fixed. ALL SEVEN targets now BUILD the compiler -- i386, aarch64, arm32, riscv32, wasm32, native x86_64, and xtensa with `--platform=posix --xtensa-long-calls`. The two blockers this ticket was left waiting on are both in `done/` (riscv32 `jal` reach, xtensa >32 KB frame), so neither of the two remaining causes it named is a cause any more. ONE defect remains and it is the FOURTH one, the one this ticket found last: the arm32 cross-built compiler builds and then SEGFAULTS under qemu-arm on `hello.pas`, while the i386, aarch64 and riscv32 cross-built compilers each run and emit a binary that runs and prints correctly. Two open sub-questions, neither measured: the i386 cross-built compiler faults ~30s into rebuilding the COMPILER (small programs are fine), and the xtensa binary cannot be exercised on this host -- qemu-xtensa carries no ESP32 core and SIGILLs on every model it does have, which is a HOST limit and not a measured defect. Under the default platform xtensa refuses `compiler.pas` at ParamStr by design (an ESP image has no argv), which is a target contract, not this bug. The title is false as written and was false when filed: wasm32 built all along."
---

# No cross target can build the compiler itself

## Measured

Binary: self-host fixedpoint at HEAD. Probe:
`compiler/pascal26 --target=<t> compiler/compiler.pas <out>`, judged on **exit
code and whether the artifact exists** — see the method note below, because
judging it on the word `error:` gives a false pass.

| target | result |
| --- | --- |
| i386 | `cpreproc.inc:2105  target i386: LoadFile expects a managed-string destination` |
| aarch64 | same site, same message |
| arm32 | same site, same message |
| riscv32 | `error: target riscv32: jal displacement 2166232 is outside the encodable range` |
| x86_64 | builds (this is the native self-host) |

**The site is real and was checked rather than trusted** — `cpreproc.inc:2105` is

```pascal
  LoadFile(CPrepPath, CPrepInclude[depth]);
```

which matches the message exactly. (Worth saying because a *different* corpus
diagnostic the same evening named a file that had nothing to do with the fault;
on this one the coordinate holds up.)

## Two defects, not one

**i386 / aarch64 / arm32 are one bug.** Identical site, identical message. Whatever
`LoadFile`'s destination is on those backends, it is not the managed string the
lowering expects, and it is presumably shared between the three because they are
the non-x86_64 "small pointer or different ABI" set.

**riscv32 is a separate bug** and is about *reach*, not types: a `jal` displacement
of 2.1 MB exceeds the encodable range. That is the same family as
[[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]] —
a backend that cannot widen a long call for a big image. The compiler is simply
the biggest program we have, so it is the first to hit it.

Fixing the `LoadFile` one does not fix riscv32 and vice versa.

## What still works, so nobody over-reads this

Ordinary programs cross-build and **run** on these targets. Verified: a hello
program and the ~700-proc kiosk app both cross-built for aarch64 and ran — the
kiosk app under `qemu-system-aarch64` on a real kernel, printing correct answers.
So this is not "aarch64 codegen is broken"; it is specifically the compiler that
cannot be built for a cross target.

## Why it matters

It is the blocker for the cross-CPU arm of
[[feature-busybox-kiosk-selfhosting-target]] rung 4, and it is why
`tools/mkkiosk.sh --arch=aarch64` ships an image with **no compiler in it**.
It is also the concrete mechanism behind
[[bug-a-the-cross-self-host-proof-runs-a-different-configuration-than-the-native-one]]:
the cross self-host proof runs a different configuration because the honest one
does not build.

## Method note — judging this probe on `error:` gives a FALSE PASS

My first sweep reported riscv64 as **BUILDS** because I grepped the output for
`error:` and found none. There is no `riscv64` target — the compiler answered
`unknown option: --target=riscv64`, which contains no `error:` — and no artifact
was produced. The valid names are `x86_64 i386 aarch64 arm32 riscv32 xtensa
wasm32` (`--list-targets`).

**Judge a build probe on the exit code and the artifact, never on the text.** Same
shape as the other false greens this evening: the instrument answered a question
adjacent to the one asked.

## Gate

`make compiler/pascal26` plus the probe table above regenerated.


## Addendum (frankS, 2026-08-30): three targets fixed, and the table was incomplete in three ways

### Regenerated, all seven targets — the original measured four

| target | before | after |
| --- | --- | --- |
| i386 | `LoadFile expects a managed-string destination` | **builds**, 12.0 MB |
| aarch64 | same | **builds**, 22.0 MB |
| arm32 | same | **builds**, 23.3 MB |
| riscv32 | `jal displacement 2197196 outside the encodable range` | unchanged |
| xtensa | **not measured** | `stack frame too large (> 32 KB) for a single ADDMI` |
| wasm32 | **not measured** | **builds**, 7.1 MB — *and always did* |
| x86_64 | builds | builds |

**Three corrections to the ticket as filed.** wasm32 was never broken, so *"no
cross target can build the compiler"* was false when written — four targets were
measured and the conclusion was drawn about all of them. xtensa is a **third**
defect, not the reach problem the ticket predicted it would share with riscv32.
And arm32 turns out to have a **fourth**: it builds, and the resulting compiler
segfaults (below).

### The fix, and why it is one change rather than five

`cpreproc.inc`'s `LoadFile(CPrepPath, CPrepInclude[depth])` has an **array
element** destination. x86-64 grew a slot-address arm for that
(`EmitLoadFileManagedAt`); the other five accept only `IR_LOAD_SYM` and error
out. So the compiler died on that one line everywhere.

**Normalised in the frontend instead** — when the destination is not a plain
identifier, `LoadFile(p, Arr[i])` becomes `tmp := <loaded>; Arr[i] := tmp`,
which is an ordinary managed-string assignment every backend already implements.
Same desugar, same `ASTKind <> AN_IDENT` guard and the same `AN_SEQ` return as
`for x in <non-identifier>` a few hundred lines above it in the same file.

The alternative was five hand-encoded slot-address arms, in five instruction
sets, to reach a shape the assignment path already reaches on all of them — the
fifth copy of a dispatch that is a defect for exactly as long as the copies
agree. x86-64's `EmitLoadFileManagedAt` is left in place and is now unreachable
from this frontend; it is correct code, and deleting what you merely *believe*
is dead is its own ticket.

**It was measured to be the ONLY blocker for those three before it was written.**
A throwaway source-level edit to `CPLoadInclude` (reverted, never committed) took
i386, aarch64 and arm32 from that error to a complete build — so the backend work
was known to be unnecessary rather than assumed to be.

### They RUN, which is the half a build does not tell you

- **i386** and **aarch64**: the cross-built `pascal26`, run under qemu, compiles
  `test/hello.pas` into a working binary. That is cross-CPU compiler *execution*.
- **i386** rebuilding the compiler itself under qemu **segfaults after ~30s** —
  small programs work, the compiler does not. A 32-bit address space against a
  ~100 MB BSS is the obvious suspect and is not yet measured.
- **aarch64** rebuilding the compiler was still running past 10 minutes with no
  fault; result pending.
- **arm32**: builds, and the cross-built compiler **segfaults on `hello.pas`** —
  a fourth defect, distinct from the three above, and invisible until the build
  stopped failing first.

### Regression coverage — the hole was in the battery, not just the backends

`test/test_loadfile_into_element_and_field.pas` already existed and already
covered this exact shape. It was wired **native-only**. The cross batteries ran
`test_cross_loadfile.pas`, which loads into a **plain variable** — the shape every
backend always accepted. *A cross row that tests the shape that already worked is
the hole, not the coverage.* The existing test is now wired into all five cross
batteries (no new test file); positive control asserted — the pinned pre-fix
compiler **rejects all five** and correctly accepts the native one.

### What remains

Two tickets, filed separately because they share nothing with this one and
nothing with each other:
`bug-a-riscv32-cannot-reach-a-far-call-so-the-compiler-will-not-link` and
`bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi`. The arm32
runtime fault is folded into the second half of this ticket, which stays open.

Gate: fixedpoint converged; `tools/gate.sh quick` GREEN; the five new cross rows
executed exactly as written.


## Re-measured 2026-08-31 (frankA) — the two remaining causes are gone; only arm32's runtime fault is left

Not new work on this ticket: a **state check** of the four Track A tickets in
`working/`, which found this one still naming two causes that are both closed. Binary:
`compiler/pascal26` at self-host fixedpoint `7dd26baa7a80` (`converged after 2
round(s)`), HEAD `35a88931f`. Probe as the ticket defines it — judged on the
**artifact**, not on the text.

| target | builds? | cross-built compiler RUNS? |
| --- | --- | --- |
| x86_64 | yes (native self-host) | — |
| i386 | yes, 12.0 MB | **yes** — compiles `hello.pas`; the output runs and prints |
| aarch64 | yes, 22.1 MB | **yes** — same |
| arm32 | yes, 23.3 MB | **NO — `qemu: uncaught target signal 11`** |
| riscv32 | **yes, 20.7 MB** (was: `jal displacement ... outside the encodable range`) | **yes** — same |
| xtensa | **yes, 24.4 MB** with `--platform=posix --xtensa-long-calls` (was: `stack frame too large`) | not answerable on this host — see below |
| wasm32 | yes, 7.1 MB | not attempted |

Both spun-out blockers named under *What remains* are in `done/`:
`bug-a-riscv32-cannot-reach-a-far-call-so-the-compiler-will-not-link` and
`bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi`. This ticket was
the last thing still asserting they were open.

**xtensa needs two flags and the reason is not a defect.** Under the DEFAULT
platform, `--target=xtensa` derives `PLATFORM_ESP`, and `ir_codegen_xtensa.inc:2772`
then refuses `ArgStr/ParamStr` deliberately — *"an ESP image has not a command
line"* — so `compiler.pas`, which reads a command line, cannot be an ESP image by
construction. That is the target's contract, not this bug, and it is why a bare
`--target=xtensa` probe still shows a red line here. With `--platform=posix` it
builds.

**What is NOT established:** the xtensa binary could not be exercised. This box's
`qemu-xtensa` offers `dc232b dc233c de212 de233_fpu dsp3400 lx106
sample_controller` — no ESP32 core — and SIGILLs immediately on all of them.
Absence of a runner is not a measurement; cf. *an instrument that cannot speak
reads as a negative*.

**So the whole of what is left under this ticket is the arm32 runtime fault** —
the fourth defect, the one the original filing could not see because the build
failed first. Everything the title and the first table were about is closed.
