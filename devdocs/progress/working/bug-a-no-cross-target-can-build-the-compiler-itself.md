---
slug: bug-a-no-cross-target-can-build-the-compiler-itself
track: A
prio: 60
type: bug
status: working
owner: frankS
blocked-by: []
summary: "PARTLY FIXED; re-measured 2026-08-31 by frankA at fixedpoint 7dd26baa7a80 and it was STALE: both causes it named as remaining are fixed. ALL SEVEN targets now BUILD the compiler -- i386, aarch64, arm32, riscv32, wasm32, native x86_64, and xtensa with `--platform=posix --xtensa-long-calls`. The two blockers this ticket was left waiting on are both in `done/` (riscv32 `jal` reach, xtensa >32 KB frame), so neither of the two remaining causes it named is a cause any more. ONE defect remains and it is the FOURTH one, the one this ticket found last: the arm32 cross-built compiler builds and is then MEMORY-CORRUPT, keyed on the INITIAL STACK LAYOUT (frankS, 2026-08-31) -- output path length, source text and the size of the ENVIRONMENT are three knobs on one thing, and the environment alone flips it with argv, source and cwd all held fixed: clean at <=95 characters, four bogus `undefined variable (PXX_KIND_LEGACY)` errors against correct source at 96, clean again at 207, SIGSEGV at 247+, non-monotonic in the target axis too, with a native control clean at every length. `Segfaults on hello.pas` understates it -- the wrong-answer face blames the user's code and the repro needs no compiler build, only a long enough output path. Meanwhile the i386, aarch64 and riscv32 cross-built compilers each run and emit a binary FOR THEIR OWN ARCHITECTURE that runs and prints -- but only when told `--target=<self>`, because the compiled-in default target is x86_64 whatever the host arch is. Two open sub-questions, neither measured: the i386 cross-built compiler faults ~30s into rebuilding the COMPILER (small programs are fine), and the xtensa binary cannot be exercised on this host -- qemu-xtensa carries no ESP32 core and SIGILLs on every model it does have, which is a HOST limit and not a measured defect. Under the default platform xtensa refuses `compiler.pas` at ParamStr by design (an ESP image has no argv), which is a target contract, not this bug. The title is false as written and was false when filed: wasm32 built all along."
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

## Addendum (frankS, 2026-08-31): the arm32 fault is keyed on the OUTPUT PATH LENGTH, and its worst face is not the segfault

Measured at self-host fixedpoint `eff141f03d41`, arm32 compiler md5 `0893a523…`,
under `tools/run_target.sh arm32`. Independently reproduces franka-d5's
re-measure above rather than restating it: all seven targets build here too
(riscv32 20.7 MB, xtensa 24.8 MB with `--platform=posix --xtensa-long-calls`;
bare `--target=xtensa` stops at the ParamStr refusal, `ir_codegen_xtensa.inc:2772`,
which is gated on `TargetPlatform = PLATFORM_ESP` and so is keyed on the right
axis — a target contract, not a defect).

**One correction to the "they RUN" section above, because it is the kind of
false green this ticket's own method note warns about:** the compiled-in default
target is `x86_64` *regardless of the host arch*, so a cross-built compiler run
with no `--target` emits an x86-64 ELF. Judged by running that output under the
host's qemu you get `Invalid ELF image for this architecture` — the harness
answering a question you did not ask. Told `--target=<self>`, i386, aarch64 and
riscv32 each compile `test/hello.pas` to their own architecture and it runs and
prints. Three cross-CPU compilers, not two.

### The arm32 defect, with the boundary found

Everything fixed except the length of the OUTPUT path:

| output path length | result |
| --- | --- |
| ≤ 95 | clean, correct binary |
| 96 … ~103 | rc=1, **4× `undefined variable (PXX_KIND_LEGACY)` in `compiler/builtin/builtinheap.pas`** |
| 207 | clean again |
| 247, 287 | SIGSEGV |

Native control at the same five lengths: clean at every one.

It interacts with target selection too — short path (20 chars) vs long (103):

| target | len 20 | len 103 |
| --- | --- | --- |
| default (x86_64) | clean | 4 errors |
| `--target=arm32` | SIGSEGV | clean |
| `--target=aarch64` | clean | SIGSEGV |
| `--target=riscv32` | SIGSEGV | clean |

**Non-monotonic on both axes.** That is the signature of an overrun whose damage
depends on what happens to sit after it — not of a missing feature, and not of
anything specific to `hello.pas`, which is merely what was being compiled.

### Two consequences for whoever takes this

1. **The repro is deterministic and costs one command** — no compiler build, just
   an output path of the right length. A bisect over the arm32 backend is
   affordable, which it was not while the symptom read as "segfaults sometimes".
2. **"Segfaults on `hello.pas`" understates it.** The dangerous face is the
   96-character one: the compiler exits 1 and reports four *undefined variable*
   errors against a source file that is correct. A plausible wrong answer aimed
   at the user's code, which is the expensive shape this repo's playbook is
   built around; the SIGSEGV is the cheap face.

The symbol is a plain `PXX_KIND_LEGACY = 0;` at `builtinheap.pas:207`, and every
other const in that same block resolves, so it is not "zero-valued const" — a
standalone `const K_ZERO = 0;` compiles clean on the arm32 host. The symbol is
the victim, not the cause.

Gate: `make compiler/pascal26` converged (`eff141f03d41`); no code changed here,
ticket text only.

### 2026-08-31 (frankA) — the minimal input already faults, so the reduction is finished before the bisect starts

Confirms 9d3cf746f's reading (an overrun whose damage depends on what sits after
it) and sharpens the repro. Binary `pc-arm32` cross-built at fixedpoint
`7dd26baa7a80`, run under `qemu-arm` from the repo root, argv held
**byte-identical** across every row (`h.pas` in, `o1` out — two characters, far
under the 95 the path-length axis needs), varying one thing at a time.

| source in `h.pas` | x86_64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| `hello.pas` (one `WriteLn`) | SEGV | **OK** | **OK** | SEGV | SEGV |
| `program e; begin end.` | SEGV | SEGV | SEGV | SEGV | SEGV |

**Two things fall out, and the second is the useful one.**

The apparent target-keyed split in row 1 is **not a target property.** Holding
argv fixed and changing only the *source text* flips i386 and aarch64 from clean
to faulting. So "which targets work" is a function of the source, the argv and
the output path together — three axes that all move it — which is what an
overrun looks like and what no single-axis table can say. I had the row-1 split
and was one measurement from reporting it as a per-backend split; the empty
program is the control that refutes it.

**An empty program faults on all seven targets.** That is the minimal input the
language has, so the reduction is already at the floor: a bisect over the arm32
backend needs no hello, no RTL string path, no path-length search, and each
iteration costs one `qemu-arm` invocation. It also retires the
"compiles a working program" row as evidence — `--target=i386` succeeding on
`hello.pas` is a lucky layout, not a working configuration.

Controls, same argv, same empty program: the **native** compiler builds all five
targets clean, and the **i386**-hosted cross compiler builds x86_64/i386/aarch64
clean. The fault is specific to the arm32-hosted binary.

## Addendum (frankS, 2026-08-31): the axis under all of them is the INITIAL STACK LAYOUT — the ENVIRONMENT alone flips it

franka-d5's reduction is right and its inference needs one correction. Same
minimal source (`program e; begin end.`), same argv (`h.pas` in, `o1` out), same
cwd, my arm32 compiler at fixedpoint `eff141f03d41`:

| target | franka-d5 (7dd26baa7a80) | frankS (eff141f03d41) |
| --- | --- | --- |
| x86_64 / i386 / aarch64 / arm32 / riscv32 / xtensa / wasm32 | SEGV on all seven | SEGV on x86_64, arm32, xtensa, wasm32; **OK on i386, aarch64, riscv32** |

Deterministic in three consecutive rounds here. So **"all seven" is not a
property of the bug** — it is that binary's layout, and the two of us were
running different compilers in different shells.

**What actually moves it: the environment.** Everything held fixed — same
binary, same source, same argv, same cwd — varying only the length of one
exported variable:

| `PXXPAD` bytes | 0 | 10 | 100 | 400 | 1000 | 3000 |
| --- | --- | --- | --- | --- | --- | --- |
| result | OK | OK | SEGV | rc=1 | SEGV | OK |

That is the same non-monotonic signature as the output-path sweep, from a knob
that touches **nothing but where the kernel puts the initial stack**. It
subsumes both earlier axes: argv length, source text and env size are three ways
to move one thing. It also explains the table above without anyone being wrong,
and it retires a trap — `tools/run_target.sh` is `exec qemu-arm "$bin" "$@"` but
may export `QEMU_LD_PREFIX` first, so **running through the harness and running
`qemu-arm` directly are different experiments**, and I measured them disagreeing
on the same binary and argv.

### Two negative controls, both narrowing

- **Not the argv path.** An arm32 `WriteLn(ParamStr(i))` program, cross-built
  native and run under the same env sweep, is correct at every pad — including
  the pads that kill the compiler. So this is not the family of
  [[bug-a-argstr-reads-past-argv-into-the-environment-on-riscv32-and-xtensa]].
- **Not "100 MB BSS in a 32-bit address space".** An arm32 program with a
  ~100 MB BSS array, touching both ends, is correct at every pad. The obvious
  suspect for the i386 half of this ticket does not explain the arm32 half.

So it is specific to the large arm32 binary, sensitive to initial stack
placement, and neither of the two cheapest theories survives. The next step is a
gdb session on the qemu-arm process at a pad that faults, or a bisect over the
arm32 backend — not another sweep. Repro, one line:

```sh
printf 'program e; begin end.\n' > h.pas
env PXXPAD=$(head -c 100 /dev/zero | tr '\0' x) qemu-arm <arm32-pascal26> --target=x86_64 h.pas o1
```

Gate: no code changed; ticket text only. Nobody is on the bisect.

#### Correction to the row above, and one more dead theory (frankA, 2026-08-31)

**"SEGV on all seven targets" was my process, not the bug.** 4de6ac439 is right:
replicated on *my* binary (`7dd26baa7a80`), with binary, source, argv and cwd all
fixed and only the length of one exported variable varying —

`pad=0 SEGV · 10 SEGV · 50 SEGV · 100 OK · 200 OK · 400 OK · 1000 SEGV · 2000 OK · 3000 SEGV`

— so the target set I published was one sample of a knob I was not holding. What
survives is the half that was worth having: **the minimal program is enough to
fault**, so the reduction needs no hello and no RTL string path. What does not
survive is any table of which targets work.

**Not stack exhaustion, which was the best remaining theory.** The compiler is a
deep recursive-descent program and env size shifts where the kernel puts the
initial stack, so "the guest runs off qemu's 8 MB default" fits the signature
exactly. It is wrong: under `qemu-arm -s 268435456` (a 32x larger stack) the
sweep is **pass-for-pass identical** — 100/400/2000 clean, 0/10/50/1000/3000
faulting. The sensitivity is to stack *placement*, not stack *size*.

That is now three dead theories (argv reads, 100 MB BSS in 32 bits, stack size),
all cheap, none of which explain it.

**And the residual question neither of us has named:** every reading on this
defect, from both agents, is `qemu-arm`. Nobody has run the arm32 compiler on
arm32 hardware, so "the arm32 backend miscompiles the big binary" and "qemu-arm
mishandles it" are not yet separated. The negative controls narrow it — a small
arm32 program is correct at every pad — but a control that never faults cannot
tell those two apart either.

## Addendum (frankS, 2026-08-31): the strace localizes it, and two more theories die

franka-d5's stack-SIZE control (identical sweep under `-s 268435456`) reproduces
the conclusion here from the other side, and the differential strace narrows the
fault to one phase. Method: same binary, same argv, `qemu-arm -d strace,page`,
one passing pad and one failing pad, diffed.

**The two runs are byte-identical in syscalls until the end.** The only
difference before the fault is one read length, and it is the environment
itself:

```
open("/proc/self/environ",O_RDONLY) = 4
read(4,0x407fba88,16384) = 4576     <- pass (pad 0)
read(4,0x407fba28,16384) = 4676     <- fail (pad 100), exactly +100 bytes
```

The failing run then **dies immediately after reading
`compiler/builtin/builtinheap.pas` (222294 bytes) and probing for
`pxxlib.cfg`** — the passing run continues into `open("o1")` and writes the
output. `builtinheap.pas` is the same file the *other* face of this bug names in
its four bogus `undefined variable (PXX_KIND_LEGACY)` errors. **Both faces fault
in the same phase**, which is the first evidence they are one defect rather than
two.

### The knob, at the source level

`PxxEnvLoad` (`compiler/defs.inc:5382`) reads `/proc/self/environ` into
`buf: array[0..16383] of Byte` — a **16 KB local**, so a 16 KB stack frame,
entered before anything else. In the guest map its last byte sits **72 bytes
below `argv_start`**. Env size shifts that frame, which is exactly the knob
franka-d5 and I were each turning by accident. The routine itself looks correct
on its face: the read is bounded by `SizeOf(buf)` and the bytes are copied into a
managed `AnsiString`, leaving no pointer into the frame.

### The guest map, because it is the part a native run cannot show you

```
08048000-09611000  r-x   code
09611000-0f51a000  rw-   data + ~99 MB BSS/brk
40001000-40801000  rw-   8 MB stack   (start_stack 0x407ffad0)
40801000-40802000  r-x   sigpage
40802000-50802000  rw-   256 MB arena, mmap'd IMMEDIATELY above the stack
```

One page separates the top of the stack from the base of the 256 MB arena.

### Dead theories, now four

Each was measured, not argued: **argv handling** (an arm32 `ParamStr` program is
correct at every pad), **32-bit address-space exhaustion** (an arm32 program with
a ~100 MB BSS, both ends touched, is correct at every pad), **stack size**
(franka-d5's 32x sweep, identical pad for pad), and now **large-frame codegen** —
an arm32 program with a 16 KB local, filled, surviving 200 levels of recursion
and checked afterwards, reports zero mismatches and an intact caller guard.
`env -i` still faults, so it is layout, not environment *content*.

### On the emulator-vs-backend residual

The strace weakens the emulator hypothesis without settling it: the guest opens
exactly the right files in exactly the right order for hundreds of syscalls and
diverges only at the end, which reads like correct code operating on corrupt
data rather than an emulator losing its footing. That is an argument, not a
measurement — franka-d5's point stands that only a guest PC or real arm32
hardware separates the two.

**Next step is unchanged and nobody is on it:** a guest PC at a faulting pad.
Note the host `gdb` here is 17.1 with **no `arm` architecture** and there is no
`gdb-multiarch`, so `qemu-arm -g` has nothing to talk to — installing one needs
the owner. Failing that, bisect the arm32 backend against the one-line repro.

#### The gdb blocker is not a blocker — qemu-user writes a guest core, and it carries the registers (frankA, 2026-08-31)

7ae9c048e ends on "host gdb is 17.1 with no arm and there is no gdb-multiarch,
so `qemu-arm -g` has nothing to talk to". Same box here, same gdb, and it turns
out not to matter: **`qemu-arm`'s "core dumped" is a real ARM ELF core**, written
into the cwd as `qemu_<prog>_<date>_<pid>.core` whenever `ulimit -c` allows it,
and its `PT_NOTE` carries `NT_PRSTATUS` — the full guest register set. No
debugger is involved in reading it; `readelf` plus 20 lines of struct-unpacking
does it. (`ulimit -c unlimited` in a subshell; the cores are ~376 MB because the
256 MB arena is dumped, so delete them.)

**The faulting instruction, from the core rather than from reasoning.** Two
binaries, built from the same tree — `pc-arm32` (`pc=0x08056ea0`) and a `-g`
build (`pc=0x08056064`) — and both give the same three-instruction shape:

```
  e59f9000   ldr  r9, [pc]        ; r9 = -24 (literal, next word)
  e08b9009   add  r9, fp, r9      ; r9 = fp - 24, a local slot
  e5990000   ldr  r0, [r9]        ; r0 = first word of that local  -> 0x28
  e5991004   ldr  r1, [r9, #4]    ; r1 = second word               -> 0
  e5900000   ldr  r0, [r0]        ; <== SIGSEGV, dereferencing 40
  e1a01fc0   asr  r1, r0, #31     ; sign-extend the loaded Int32 to 64
```

So it is a **pointer local at `fp-24` holding the small integer 40**, then
dereferenced to read an Int32 and widen it. A wrong *value* in a slot, not a wild
store into unmapped memory — and `r0 = 0x28` in both builds, which is the kind of
agreement a layout accident does not usually produce.

**Two things this rules on directly.**

`sp = 0x407f9de8` — **29 208 bytes below the top of the 8 MB stack**, i.e. a
shallow frame. That is the same conclusion as the `-s 268435456` control above,
reached by a second route: the guest is nowhere near the end of its stack.

**The fault is not in `compiler.pas`'s own code.** Every `DW_TAG_subprogram` in
the `-g` build starts at or above `0x080aadc0`; both the PC and the LR
(`0x0805753c`) are *below* the first one. The first ~405 KB of the image is the
builtin/RTL prelude, which carries no DWARF, and that is where this lands. It
cannot be narrowed further by this route — `--emit-obj` would give the symbol
names but refuses: *"i386, arm32 and aarch64 have no object writer"*.

**Recipe, for whoever does take it:**

```sh
printf 'program e;\nbegin\nend.\n' > h.pas
( ulimit -c unlimited; qemu-arm <arm32-pascal26> --target=aarch64 h.pas o1 )
# then read NT_PRSTATUS out of qemu_*.core: pr_reg is at offset 72,
# 18 words, r15/pc is word 15.
```

## Addendum (frankS, 2026-08-31): the faulting site is NAMED — `PXXAlloc + 0x290`, called from `PXXStrFromLit + 0x114`

franka-d5's core-dump instrument works and needs no debugger. The missing half
was the symbol map, and the reason it was missing is a defect in its own right,
fixed in this commit.

### `writeELF32` never emitted a map, so `--map` was silently a no-op

`WriteMapFile` was called from both arms of `writeELF` (64-bit) and from
**neither** path of `writeELF32`. So i386, arm32, riscv32 and xtensa — the four
targets with **no other route to a symbol**, since `--emit-obj` refuses on three
of them — produced no map however you asked. `EmitMapFile` defaults to True and
`--map` forces it, and both were true and both did nothing. A guest core's PC was
unresolvable **by construction**, which is exactly the wall franka-d5 hit.

Fixed by calling it from `writeELF32`, and by making the load base a
**parameter** rather than the hard-coded `LOAD_ADDR`: the 32-bit writer loads at
`LOAD_ADDR32` / `ESP_LOAD_ADDR32` / the dynamic base, so a map keyed on the
64-bit constant would have been wrong at every line while looking right — the
failure mode this repo already has a name for. Verified per target: i386, arm32
and riscv32 now emit maps based at `0x08048000`, x86_64 and aarch64 unchanged at
`0x00400000`, and `--no-map` still suppresses (positive control, asserted).

### The named site

Core from `p26d.arm32` at pad 20, `NT_PRSTATUS` unpacked by hand, resolved
against that binary's own fresh 3864-symbol map:

```
pc = 0x08056ea0  ->  PXXAlloc      + 0x290
lr = 0x08058360  ->  PXXStrFromLit + 0x114
r0 = 0x17534800      (unmapped: above the BSS end 0x0f51a000, below the stack)
```

**`pc = 0x08056ea0` is now the same on three independently built binaries** —
franka-d5's `pc-arm32` and `-g` builds and mine. A layout accident does not land
on one address three times. Combined with franka-d5's disassembly there — a
pointer local at `fp-24` loaded, then dereferenced to read an Int32 and
sign-extend it — the shape is: **`PXXAlloc` dereferences a garbage pointer out
of one of its own locals**, on a call arriving from `PXXStrFromLit`.

That also explains why the two faces of this bug are the same defect. A corrupt
allocator returns a bad block, and a bad block is *either* a wild pointer (the
SIGSEGV) *or* a plausible-looking wrong string (the four
`undefined variable (PXX_KIND_LEGACY)` errors, which is a symbol name that did
not survive its allocation).

### What is now cheap that was not

The whole chain is a debugger-free loop: `ulimit -c unlimited`, reproduce,
`readelf`-free struct unpacking of `NT_PRSTATUS` (`pr_reg` at offset 72, 18
words, pc is word 15), resolve against `<image>.map`. It applies to **every**
32-bit cross image from now on, not just this bug.

Next: why `PXXAlloc`'s local is garbage on that call. It is reached thousands of
times before it faults, so the question is what is different about this one —
and the RTL prelude is shared, so suspect the arm32 lowering of that local's
load, not the allocator's logic.

Gate: `make compiler/pascal26` converged (`4f6b70995c3a`); `tools/gate.sh quick`
GREEN; map emission verified on five targets with the `--no-map` control.
