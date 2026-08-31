---
slug: bug-a-no-cross-target-can-build-the-compiler-itself
track: A
prio: 60
type: bug
status: working
owner: frankS
blocked-by: []
summary: "PARTLY FIXED 2026-08-31 (frankA) -- one root cause found and fixed, and the ticket is NOT closed: the arm32 cross-built compiler now compiles a small program cleanly (9 of 9 pad layouts, rc=0, real output, zero heap diagnostics, where the pre-fix binary reported at EVERY pad) but STILL SEGFAULTS compiling `compiler.pas` itself. It is a SECOND DEFECT and it is now split out as [[bug-a-the-arm32-hosted-compiler-wants-4x-the-arenas-and-dies-unchecked-at-enomem]]: the arm32-hosted build maps FIFTEEN 256 MiB arenas and the fifteenth returns ENOMEM, where the native build of the same source uses FOUR. The heap debugger is silent on it -- zero reports of every family on an instrument that fires on plant controls -- so it is not this ticket's write-after-free. The cause that WAS found is one instruction width. All seven targets BUILD the compiler; the title was false when filed (wasm32 built all along) and the two blockers this ticket waited on are in `done/`. The last defect -- the arm32 cross-built compiler corrupting its own heap -- was `EmitLoadVar`/`EmitStoreVar` on arm32, riscv32 and xtensa sizing a variable access with `TypeSize(Syms[idx].TypeKind)`, which is the ELEMENT type. A dynamic array's slot holds a pointer-sized handle, so a byte-sized element gave a ONE-BYTE access to a pointer slot: the prologue zero-init emitted `strb` and cleared only the low byte, leaving three stale ones. The early-`Exit` cleanup in `EmitLateNestedSpecDecls` then released a handle made of stack garbage and `PXXDynArrayReleaseDepth` decremented a refcount inside an already-freed block, which is the `pxx-heap: WRITE AFTER FREE` this ticket chased. aarch64 has carried the guard for this since the same defect was found there; it was never applied to the three siblings -- six sites, three backends, both directions. THE PROOF: all 34 stale handles reported across the pad sweep end in `0x00`, which a byte-store must produce and nothing else does; plus the disassembly (`+0x0044` `e5c90000` STRB before, `e5890000` STR after, same function, same address). VERIFIED: the arm32 cross compiler over pads 0..80 in one shell went from reporting at EVERY pad (rc 0/139/204/1) to 9-of-9 clean, rc=0, with real output. SCOPE, measured and narrower than it looks: the obvious user-level repro (`array of Byte`, `b := a`) passes on the PRE-FIX compiler too, so a declared dynarray variable does not take this path -- do not claim ordinary user code is affected without a repro that fails before the fix. riscv32 and xtensa carried the identical defect and measured clean on this workload; their zero was luck, not health, which is why the fix went to all three. Instrumentation added along the way (PXX_HEAP_DEBUG kinds 8/9/10/11 plus a raw stack capture) is committed and each check has an end-to-end plant control."
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

#### The faulting statement is the free-list POP, so the corruption is older than the call (frankA, 2026-08-31)

With 59c2d85d2's map I disassembled `PXXAlloc` in a fresh arm32 build
(`4f6b70995c3a`, `--map`, `PXXAlloc` at `0x08056c10`, so the fault is `+0x290`
as frankS resolved it). Decoded, `+0x1fc` through `+0x290` is exactly
`builtinheap.pas:1104-1108`:

```
+0x1fc  r9 = fp-68 ; r0 = [r9]        bin
+0x204  r0 <<= 3   ; + base           FreeBins is array of Int64 -> *8
+0x210  r0,r1 = [FreeBins+bin*8]      cur := FreeBins[bin]
+0x224  [fp-24] = r0,r1               (cur, a 64-bit local)
+0x240  64-bit compare of [fp-24] vs 0, beq away      if cur <> 0 then
+0x288  r0,r1 = [fp-24]
+0x290  ldr r0,[r0]   <== SIGSEGV     FreeBins[bin] := PWord(cur)^;   { pop }
+0x294  asr r1,r0,#31                 sign-extend: PWord = ^NativeInt, 4 bytes here
```

**So nothing is wrong with this call.** `cur` is a free-list head that passed
`<> 0` and is not a readable address — the bin was already poisoned when
`PXXAlloc` was entered. That answers frankS's "PXXAlloc is reached thousands of
times before it faults, so what is different about this call": nothing is. It is
the first pop of a corrupt bin, and the bins only fill after frees, which is also
why it takes thousands of calls to arrive. **The hunt is the writer, not the
allocator** — and not the arm32 lowering of that load, which decodes correctly
(`PWord = ^NativeInt` is 4 bytes here, sign-extended into the `Int64` slot, which
is right for an address below 2 GB).

**A collision worth checking, stated as a hypothesis and not a finding.** The
next-link is written at `PWord(addr)^`, i.e. at the block base — and
`PXX_HDR_META = 0` (line 192), so the managed META/kind word is at *the same
eight bytes*. A live free-list link and a stale meta write occupy one slot by
design. My `r0 = 0x28` is 40, which is a plausible small header value and not a
plausible address. **The objection to it, which I could not clear:** that
aliasing is identical on x86-64, so it cannot by itself explain an arm32-only
fault. Either it is benign (nothing writes META after free, as intended) and the
real bug is a stale writer that only wins the race here, or the arm32 half is
elsewhere. Catching the writer settles it; studying `PXXAlloc` will not.

**One instrument warning, because it bit me.** I swept a `-dPXX_HEAP_DEBUG` build
scoring pass/fail on "was the artifact produced", and that build is slow enough
that the tool timeout killed runs mid-compile — a killed run produces no artifact
and scores identically to a SIGSEGV. Those rows were not measurements and are not
reported here. On this defect, score the bash SIGSEGV notice, not the artifact.

## Addendum (frankS, 2026-08-31): the corrupt bin head is STRING PAYLOAD — this is a use-after-free, not a stale meta write

franka-d5's localisation to the free-list pop holds, and their aliasing premise
checks out rather than merely sounding right: `PXXFree(p)` writes the next-link
at `PWord(addr)^` where `addr` is the raw pointer `PXXAlloc` returned, and that
same address IS the managed block base, so `PXX_HDR_META = 0` aliases the link
exactly. Worth stating because the constant is an offset from the BLOCK BASE and
the link is written at the *payload* address — two names for one address only if
you check which pointer the free path is handed.

**Their objection is answered by the data, and it retires their own hypothesis.**
Four cores at four pads, same binary (`p26d.arm32`, fixedpoint `4f6b70995c3a`),
resolved against its map:

| pad | corrupt bin head | bytes | lr |
| --- | --- | --- | --- |
| 20 | `0x17534800` | `00 48 53 17` | `PXXStrFromLit+0x114` |
| 50 | **`0x72616843`** | **`43 68 61 72` = `"Char"`** | `PXXStrSetLen+0x1b0` |
| 80 | `0x187df800` | `00 f8 7d 18` | `PXXStrFromLit+0x114` |
| 200 | `0x7c54c000` | `00 c0 54 7c` | `PXXStrFromLit+0x114` |

`pc = PXXAlloc+0x290` in all four, a fifth and sixth independent confirmation of
the site. **One of the values is the ASCII string `Char`** — a Pascal identifier
out of the compiler's own token stream.

A stale META write cannot produce that: meta is a small kind/flag word, which is
what franka-d5's `0x28` looked like and why the hypothesis was reasonable. String
payload at a free-list head means **the block was written while it was on the
free list** — a use-after-free write, or the same block handed out twice and one
holder writing into it while the other still has it linked. `PXXStrFromLit` and
`PXXStrSetLen` as the two `lr` values fit: both write string bytes at the base.

That reframes the arm32-only question. A use-after-free in shared RTL code should
break x86-64 too, so the arm32 half is most likely **which address gets freed or
written**, not the allocator's logic — an off-by-header or a size computed with a
64-bit assumption would put a write into a neighbouring free block. `PXX_HDR_SIZE
= 24` with 4-byte `PWord` on 32-bit is the place to look first.

**Next, and cheap:** `-dPXX_HEAP_DEBUG` makes freed bytes `$DD` and quarantines
rather than recycling, so a UAF write is caught at the write. Heed franka-d5's
instrument warning when running it: that build is slow enough that a tool timeout
kills runs mid-compile, which produces no artifact and scores identically to a
SIGSEGV. **Score the SIGSEGV notice, never the artifact.** The open fork is
double-free versus write-after-free; `-dPXX_OBJTRACE` plus `grep <addr>` answers
which.

Gate: no code changed in this addendum; cores deleted (376 MB each).

#### The allocator's own detector names it: WRITE AFTER FREE (frankA, 2026-08-31)

a11f98f86's fork — double-free versus write-after-free — is settled by the debug
heap, which distinguishes them by design (`DBG_M1..M4`: DOUBLE FREE, WRITE AFTER
FREE, RETAIN of a FREED object, RELEASE of a FREED object). Built at
`4f6b70995c3a`, `--target=arm32 -dPXX_HEAP_DEBUG`, minimal source, pad 20:

```
pxx-heap: WRITE AFTER FREE in 0x448f5ff0
```

So it is **not** a double free and **not** a retain/release of a freed object;
something writes into a block that is already on the free list. That is the
mechanism a11f98f86 inferred from the `"Char"` bytes, now stated by the allocator
rather than by us.

**A second site, same routine, different caller.** Four stock cores at
`4f6b70995c3a`, one per pad:

| pad | pc | lr | r0 |
| --- | --- | --- | --- |
| 20 | `PXXAlloc+0x290` | `PXXStrFromLit+0x114` | `0x7990c800` |
| 50 | `PXXAlloc+0x290` | `PXXStrFromLit+0x114` | `0x13e27000` |
| 80 | `PXXAlloc+0x290` | `PXXStrFromLit+0x114` | `0x148b8000` |
| 200 | **`PXXAlloc+0x578`** | **`PXXDynSetLen+0x560`** | **`0xfffffff9`** (= -7) |

`+0x578` is the LARGE-block first-fit walk, not the bin pop, and `-7` is a length
or size rather than an address. Same corruption, two different consumers of it.

**One claim of mine WITHDRAWN, and the reason matters more than the claim.** I
measured the i386 cross compiler failing on the minimal program at 5 of 15
environment pads and was about to report that the defect is 32-bit-wide rather
than arm32-only. **It does not reproduce**: 18 pads clean in one sweep, and pad
1000 clean in five consecutive runs. The failing measurement was taken while the
background arm32 sweep was still running on the same box, so it is load, not
layout. **A pad number is not portable across shell invocations either** — the
pad shifts an absolute layout that already depends on the whole environment, so
"pad 1000 faults" is a statement about one process, not a reproducible coordinate.
Sweep a range inside one shell; never carry a single pad between them.

The residual from the earlier note stands unchanged: every reading is still
`qemu-arm`, and the WRITE AFTER FREE detection does not separate a real UAF from
an emulator artifact — it says what the guest's own bookkeeping saw.

#### Every arm32 report is a DECREMENT, and one attractive lead is dead (frankA, 2026-08-31)

Instrument: 252bfe4a3, arm32 image `901a553a85610e1d`, 15 pads swept inside one
shell, scored on the `pxx-heap:` notice.

**26 reports, and the value field is unanimous.** Every one is `val=0x...dc` —
a single poison byte decremented by one, `0xDD -> 0xDC`. Not one contains data.
So on this build nothing SCRIBBLES; something DECREMENTS. `PXXHdrRC(p)` is
`base + 8`, and `off=0x08` is the single commonest row, so this is a refcount
release landing on a block that is already free.

**The offsets are not a displaced base.** Cross-tab against size class:

| block size | offsets seen |
| --- | --- |
| 0x20 (32 B) | 0, 8, 0x10, 0x18 — *all four* 8-aligned slots |
| 0x28 (40 B) | 0, 8, 0x10, 0x20 |
| 0x30 (48 B) | 0, 8, 0x10, 0x18, 0x20, 0x28 — *all six* |

Uniform across each block, bounded only by that block's own size, with no
correlation to size class. A displaced-base story predicts a cluster; this is
the dangling-handle picture — a stale handle released later, its rc slot landing
wherever it points, 8-aligned because rc slots are. So this is a refcount
LIFETIME bug (an over-release or a missing retain), not header arithmetic.

**Target matrix, same instrument, same workload:**

| target | how it runs | reports |
| --- | --- | --- |
| x86-64 | native | 0 |
| i386 | **native, 32-bit, no emulator** | 0 |
| aarch64 | emulated, 64-bit | 0 |
| riscv32 | **emulated, 32-bit** | 0 |
| arm32 | emulated | **26** |

riscv32 is the load-bearing row: it shares BOTH properties arm32 has and is
silent, so neither 32-bitness nor emulation is sufficient. That retires the
`PXX_HDR_SIZE`-against-4-byte-`PWord` hypothesis (mine, and i386 kills it) and
narrows the emulator residual from "emulation" to "qemu-arm specifically",
which is a much smaller thing to still be carrying.

**The lead that died, recorded because it was the best one and lasted four
minutes.** x86-64 releases a string through a HAND-EMITTED BLOB
(`AnsiStrReleaseAddr`, `test rax,rax / dec qword [rax-16]`) and never calls
`PXXStrDecRef`; the cross backends call the Pascal routine. "arm32 releases
differently" is therefore false: aarch64 and riscv32 route exactly as arm32 does
and both are clean. Two implementations of one concept is still a real smell —
they already disagree, since the routine carries the `PXX_STATIC_RC_FLOOR` guard
and the blob's fast path does not — but it is not this bug's cause.

**Two bounds on the numbers above, frankS's, and they change how a zero reads.**
The detector can only fire while the victim is still POISONED: a dangling release
on a RECYCLED block reads a live refcount, silently decrements a stranger's
string, and is invisible here by construction. So 26 is a LOWER BOUND, never a
rate, and a zero means "none landed inside the quarantine window". That is also
a live candidate for the stock build's `Char` — a release landing on a recycled
block holding live token text corrupts data exactly that way. And the debug build
QUARANTINES rather than recycling, so it is a different lifetime universe from
the stock cores; the victim named here is not known to be the block those cores
died on.

## 2026-08-31 (frankA) — the IR differential: one divergence found, and it is NOT the cause

frankS proposed the right method and warned off the wrong one: do not diff
`ir_codegen_arm32.inc` against `ir_codegen_aarch64.inc` ("the same spelling trap
one level up"). Instead compile one tiny program, dump the **shared** IR, and
compare where each backend emits retains and releases **against that same IR** —
any divergence in placement is then purely backend. It also changes what you are
looking for from a *missing* call, which the counts have twice said is not
there, to a **misplaced** one.

### Method

`PXXDBG=a.ir:<proc>` for the IR, then a small disassembler-driver that resolves
call targets **inside one procedure** through the `--map` file (arm32
`cond|1011|imm24`, pc+8; aarch64 `100101|imm26`, pc). So the comparison is
per-call-site, not per-file-grep.

### Result 1 — placement is identical, on seven shapes

Nested call results as arguments, a record field, a dynamic array element, a
for-loop temp reassigned each round, a `const` parameter passed onward, a
two-path conditional assignment, and a build-by-append function. **Retain and
release counts and their order match arm32 vs aarch64 on all seven.** No
misplaced release was found at this granularity.

### Result 2 — one real divergence: the static-literal path is 2-of-7

`EmitStaticLitHandle` (x86-64) and `EmitStaticLitHandleA64` exist; **i386,
arm32, riscv32, wasm32 and xtensa have no equivalent.** For an `IR_CONST_STR`
node the two privileged backends hand back the pooled literal's address as a
ready-made saturated handle; the other five call `PXXStrFromLit` — a call, a
`PXXAlloc`, a copy, and a `PXXFree` per literal evaluation. For `a := 'hello'`,
arm32 emits that call and aarch64 emits none, retain/release counts otherwise
identical (5 `PXXStrDecRef` + 1 `PXXStrIncRef` on both).

That is a genuine backend divergence against a shared IR node, and it puts the
suspect population — heap-resident string literals — on arm32 and not on the
clean 64-bit target.

### Result 3 — and the control KILLS it as the cause

Single variable: force `EmitStaticLitHandleA64` to return `False`, rebuild the
host, build the aarch64 cross compiler with `-dPXX_HEAP_DEBUG`, and run it under
`qemu-aarch64` — aarch64 now heap-allocates every literal exactly as arm32 does.

**Positive control, asserted rather than assumed** (the manipulation had to be
shown to have worked): the patched host emits `PXXStrFromLit` in the probe
procedure and the stock host emits none.

| arm | literals | pads run | heap diagnostics |
| --- | --- | --- | --- |
| B — static path DISABLED | on the heap, as arm32 | 5 | **0** |
| A — stock | static blocks | 5 | **0** |

`rc=0` on every pad, both arms. `ir_codegen_aarch64.inc` restored via
`git checkout` (it carried no other uncommitted work).

**So heap-resident literals are not sufficient to produce the symptom** — which
i386 and riscv32 already implied, since both lack the static path and both are
clean. The divergence is real and is recorded on
[[bug-a-string-release-has-two-implementations-that-already-disagree]] (it
sharpens that ticket: release must now be correct under *two* ownership
conventions, an owned `rc=1` block on five targets and a saturated static block
on two). It is not this bug.

### What this leaves

The IR differential has now said "placement matches" at the granularity a
per-call-site comparison can see. Either the misplacement is in a shape not
covered by those seven, or the mechanism is not placement at all. The instrument
that can still speak is the one committed today: on arm32 — unlike x86-64 —
`PXXStrDecRef` **is** the release path, so the new poison check inside it
reports the stale release *at the moment it happens*, with the block address and
size class, rather than at quarantine eviction long afterwards.

## 2026-08-31 (frankA) — the writer, named

`PXXDynArrayReleaseDepth`, decrementing the refcount of an already-freed
dynamic array.

### How, and why it is causal rather than correlational

Every writer of a managed refcount was instrumented with the same poison check,
each reporting a distinct kind, and each check **drops the write** instead of
performing it:

| pair | kinds | arm32 compiler run |
| --- | --- | --- |
| `PXXStrDecRef` / `PXXStrIncRef` | 8 / 9 | 0 |
| `PXXObjRelease` / `PXXObjRetain` | 4 / 3 | 0 |
| **`PXXDynArrayReleaseDepth` / `PXXDynArrayIncRef`** | **10 / 11** | **2 / 0** |

With the dynarray check in place the run reports **zero `WRITE AFTER FREE`**,
where the same binary shape previously reported six. The write-after-frees were
that decrement: suppress it and they stop existing. Nothing else changed.

```
pxx-heap: RELEASE of a FREED dynarray 0x41f03a00  size=0x44d95128
pxx-heap: RELEASE of a FREED dynarray 0x41f01400  size=0xdddddddd
```

**Do not read the `size=` field on a kind-10/11 row.** It is the allocator's
size word below the block, and for a stale handle that word is itself poison or
already reused — the second row reads `0xdddddddd` and says so plainly. The
field is meaningful on the write-after-free rows, which are reported from the
quarantine and know the real block; it is noise here, and it should probably be
dropped from these two kinds.

`rc=139` (SIGSEGV) with the check active: dropping the write forks the
trajectory, so per frankS's bound only the FIRST report ties to stock behaviour.

### What made this readable at all: two dead instruments, back to back

1. **The stale-string check appeared to say "not the string path".** It fetched
   the block size through `PXXHdrBase`, which under `PXX_HEAP_DEBUG` `Halt(204)`s
   when the kind byte exceeds `PXX_KIND_MAX` — and `$DD` poison always does. So
   the check fired and the process died one statement before `PXXDbgFlush`.
   Output empty, on every target that calls the routine at all. The tell was the
   exit code: **204 is a deliberate diagnosis, not a crash**, which proved the
   check had fired and located the silence to a single statement.
   My "positive control" for it had been *the message string is present in the
   image* — a control on a neighbouring property, which proves the code was
   compiled in and nothing about whether it can speak. Every check here now has
   an **end-to-end plant control** (`uafdec.pas -dPLANTDEC`,
   `uafdyn.pas -dPLANTDYN`): plant a stale handle, see the line, and see the
   clean arm stay silent. Both pass on arm32 and aarch64.
2. **The call differential silently reported nothing for dynarrays**, because
   the decoder filtered call targets against a name whitelist built for the
   string path. Every row came back "same", vacuously. Rewritten without the
   whitelist — and its aarch64 half then reported nothing at all, which was a
   second dead instrument (ELF64 program-header fields read at the wrong
   offsets) and not a finding either.

### What the differential says once it works

Eight dynamic-array lifetime shapes — share by assignment, `SetLength` growth,
by-value and `const` parameters, a field of a record, managed elements, a
loop-carried temp, explicit `nil` — **arm32 and aarch64 emit identical
`PXXDynArrayIncRef` / `PXXDynArrayRelease` / `PXXDynSetLen` counts on all
eight.** So the stale handle is not produced by a missing or extra emitted call
in any shape tested so far.

### Next

The routine is known; the **call site** is not. Two threads, in order of cost:

1. **Re-run the other targets.** aarch64, riscv32 and i386 measured "0 reports"
   *before this check existed*, so that zero could not have seen a stale
   dynarray release. If they report kind 10 as well, the defect is shared and
   arm32's heap layout merely converts it into a fault — which would move this
   ticket's whole framing. Running now.
2. **Name the caller.** `PXXDbgFlush` is called exactly twice in this run, so a
   breakpoint on it under `qemu-arm -g` costs nothing and the unwind names the
   call site directly.

## 2026-08-31 (frankA) — ROOT CAUSE, and it is one instruction

**A dynamic array's variable slot holds a pointer-sized handle. `EmitLoadVar` /
`EmitStoreVar` on arm32, riscv32 and xtensa sized the access from the ELEMENT
type.** For a byte-sized element `TypeSize` is 1, so a pointer slot got a
one-byte access:

```
prologue zero-init:   strb r0, [r9]     clears the low byte, leaves 3 stale
handle load:          ldrb r0, [r9]     reads a truncated handle
```

aarch64 has carried the guard since the same defect was found there —
`EmitStoreVarA64`: *"TypeSize(elementType) would truncate the 64-bit handle"*.
It was never applied to the siblings. **Six sites, three backends, both
directions.**

### The signature that settles it, and it was in data already collected

`EmitLateNestedSpecDecls` is the call site. Its declared locals are three
Integers; the released thing is a compiler-synthesised dynarray temp at
`[fp-48]`, and the release sits on the function's **early-`Exit`** path — which
a trivial program takes every time. The prologue zeroes the neighbouring string
temp at `[fp-44]` with `e5890000` (`STR`, 4 bytes) and the dynarray temp with
`e5c90000` — bit 22 set, so **`STRB`, one byte.** Three stale bytes survive, the
early exit releases a handle made of stack garbage, and
`PXXDynArrayReleaseDepth` decrements a refcount inside an already-freed block.

**Every one of the 34 stale handles reported across the pad sweep ends in
`0x00`** — 34 of 34. A byte-store cannot produce anything else, and nothing else
produces that. That is the proof; the disassembly is the mechanism.

Worth recording how it was found, because it was cheap and I nearly did not do
it: the reports had been read one at a time as addresses. Sorting them and
asking what was INVARIANT took one command.

### Verification

Instruction level, same function, same address:

| | `+0x002c` (string temp) | `+0x0044` (dynarray temp) |
| --- | --- | --- |
| before | `STR` | **`STRB`** |
| after | `STR` | `STR` |

Behaviour, arm32 cross-built compiler compiling `program e; begin end.` under
`qemu-arm`, same pad range in one shell:

| | pads | rc | heap diagnostics | output |
| --- | --- | --- | --- | --- |
| before | 0…80 | 0 / 139 / 204 / 1 | reports at **every** pad | — |
| after | 0…80 | **0 on all 9** | **0 on all 9** | produced |

### How far the exposure reaches — MEASURED, and narrower than it looks

The obvious user-level repro **does not reproduce it.** `array of Byte`,
`SetLength`, element writes, `b := a`, sum and print: `len=4 sum=46 OK` on
arm32, riscv32 and aarch64, **on the pre-fix compiler as well as the fixed one.**
A repro that passes on both arms is a coincidence, not a verification, so it is
recorded here as a negative and is NOT being added as a regression test.

So a declared dynamic-array variable does not take this path. What demonstrably
does is the **compiler-synthesised temp** — the slot at `[fp-48]` above, zeroed
by the prologue pass through `EmitStoreVarArm32`. A user-level shape that
reaches the same emitter has not been found yet; shapes still being tried are a
by-value dynarray parameter, a function result passed straight into a call, two
temps in one call, and an early `Exit` before the local is assigned.

**Until such a shape is found, the honest statement of scope is: the defect is
in a width decision that is wrong for every dynamic-array slot, and the path
proven to reach it is the synthesised-temp prologue.** Do not upgrade that to
"ordinary user code is affected" without a repro that fails on the pre-fix
compiler.

riscv32 and xtensa carried the identical defect and measured CLEAN on the
compiler workload — the corruption only becomes visible when the surviving
stale bytes happen to form a plausible heap address. **Their zero was luck, not
health**, which is why the fix went to all three rather than only to the one
that crashed.

### 2026-08-31, same session — the fix is REAL but the ticket is NOT closed

The arm32-hosted build of `compiler.pas` still segfaults: `rc=139`, no output
binary, on the shipping (non-heap-debug) configuration at the fixed compiler.

So the width fix is verified on the small-program workload and settles the
write-after-free this ticket spent its length on — and it does **not** settle
the title. Something still kills the arm32-hosted compiler on a real input.
Running the full self-build under `-dPXX_HEAP_DEBUG` now: if the allocator's own
bookkeeping stays silent, this is no longer a managed-lifetime bug and the next
step is a different instrument, not more of this one.

Stated plainly because the temptation was to stop at the green: **"my repro
passed" is a different claim from "the compiler works", and here the two
diverge.**

### The heap debugger is SILENT on the self-build — this is no longer a heap bug

Full `compiler.pas` build, arm32-hosted under `qemu-arm`, `-dPXX_HEAP_DEBUG`:

```
rc=139
  total pxx-heap : 0      WRITE AFTER FREE 0    DOUBLE FREE 0
  FREED string   : 0      FREED object     0    FREED dynarray 0
```

**Zero of every kind, and the zero is not vacuous.** The same instrument fires
on the plant controls for all three families on this target, and it reported six
write-after-frees on this same workload shape before the width fix. It can
speak; it has nothing to say.

So the remaining fault is **not** a managed-lifetime bug, and continuing to
instrument the allocator is the wrong move. The residual question — "then what
kills it?" — is owned here and the next instrument is the faulting PC, taken
from the guest core `qemu-arm` writes under `ulimit -c` (no debugger: the system
gdb has no arm target and installing one needs sudo).

One caveat worth stating rather than discovering later: a *write-after-free*
report is raised at quarantine eviction, which needs enough frees to cycle the
ring, so a process that dies early could in principle carry an unreported one.
The three *stale-handle* checks have no such delay — they report at the
retain/release itself — and they are silent too, which is what makes this a
real negative rather than a timing artefact.

## Addendum (frankS, 2026-08-31): frankA's root cause INDEPENDENTLY CONFIRMED from the original symptom, not the reduced repro

Verified rather than accepted, and deliberately against the axes this ticket
opened with — a fix that closes a reduced repro is a weaker claim than one that
closes the symptom that started the hunt.

Rebuilt at HEAD (self-host fixedpoint `36bb71e851a3`, which includes
`5454ef402`), rebuilt the arm32 cross compiler from it, and re-ran **both** of my
original sweeps:

| axis | before | after |
| --- | --- | --- |
| environment pad (0…1000, 8 points) | faults at 50/80/120/200/1000, non-monotonic | **8 of 8 clean, rc=0, real output** |
| output path length (97…287, 7 points) | 4× bogus `undefined variable (PXX_KIND_LEGACY)` at 96, SIGSEGV at 247+ | **7 of 7 clean, zero errors** |

The path-length axis is the one that matters most here, because it is where the
**wrong-answer face** lived — the compiler exiting 1 and blaming correct source.
That face is gone at exactly the lengths that produced it.

**The diff matches the story.** `if Syms[idx].IsArray and (Syms[idx].ArrLen = -1)
then sz := TARGET_PTR_SIZE;` in `EmitLoadVar`/`EmitStoreVar`, three backends, and
the guard it copies is real: `EmitStoreVarA64` has carried it since it was found
on aarch64. **That is why aarch64 was the silent control** — not luck, and not
the axis anyone was proposing. It also retires the last emulator residual without
another run: a one-byte store where a word store belongs is a code-generation
defect that qemu reproduced faithfully.

**One observation of mine is still unexplained and I am not filing it as closed.**
frankA's signature is that all 34 stale handles end in `0x00`, which a byte-store
must produce. Three of my four sampled bin heads fit
(`0x17534800`, `0x187df800`, `0x7c54c000`) — but `0x72616843`, the ASCII `"Char"`,
does not. Those are different populations (a stale *handle* versus a corrupted
free-list *link*), so it is consistent as a downstream effect: a bogus handle
released → refcount decremented inside a freed block → that block later written
with live token text. Consistent is not demonstrated. It costs nothing to leave
stated.

**The ticket stays OPEN**, per frankA: the arm32-hosted build of `compiler.pas`
still faults, and their `-dPXX_HEAP_DEBUG` self-build reports zero of every family
on a non-vacuous instrument — so **the residual is not a heap bug** and is a
different defect wearing this ticket's name. Whoever takes it should read it as
such rather than as "the fix did not work".

Gate: `make compiler/pascal26` converged (`36bb71e851a3`); both sweeps above; no
code changed in this addendum.

### The residual, named: an unchecked `mmap` failure — not corruption

Guest core from the arm32-hosted `compiler.pas` build (`qemu-arm` writes one
under `ulimit -c`; the system gdb has no arm target and installing one needs
sudo, which is not worth a human's attention for this):

```
pc = 0x0805783c = PXXAlloc+0xc2c      instruction:  STR r1, [r0]
r0 = 0xfffffff4  = -12
r7 = 0xc0        = 192 = mmap2, arm32 EABI
```

`-12` is `-ENOMEM`, and 192 is the number in
`__pxxrawsyscall(192, 0, len, 3, 34, -1, 0)` at `builtinheap.pas:946`. The
disassembly corroborates the registers rather than merely agreeing with them:
`r0` is loaded from a local at `[fp-40]` and immediately written through.

And the allocator says so itself, at `builtinheap.pas:977` — *"every caller
reaches this through PXXAlloc, which does NOT check the result (deliberately --
on a hosted target a failed mmap returns a negative errno and the next access
faults), so the returned value IS the base of the heap."* That is a documented
design choice, not an oversight, and it is why an out-of-memory condition
arrives as a SIGSEGV at the first write instead of a diagnostic.

**Confidence, labelled.** The `-12` and the faulting instruction are read
directly from the core. Attributing that `-12` to *this* `mmap2` rests on `r7`
still holding 192 inside the same function — corroboration, not proof. A
`qemu -strace` census of the guest's `mmap2` calls is running to settle it.

**The open question is whether the exhaustion is legitimate.** `HEAP_ARENA` is a
**256 MiB** mmap chunk, and the native x86-64 build of the same source peaks at
**549 MB RSS** — a 32-bit build's structures are smaller, not larger, so a 4 GB
space running out looks more like arena granularity or waste than a real
ceiling. If the census shows only a handful of arenas before the failure, this
is a real 32-bit limit and belongs in a target-contract note; if it shows many,
there is a second defect here.

Either way it is **not** this ticket's write-after-free, and it should be split
out rather than extending this ticket further.

**Split, 2026-08-31:** the residual is filed as
[[bug-a-the-arm32-hosted-compiler-wants-4x-the-arenas-and-dies-unchecked-at-enomem]]
with the `-strace` counts, the guest-core registers, and the two separable
defects it contains (the arena appetite, and `PXXAlloc` not checking the `mmap`
return). Nothing further about it should be appended here.

## Addendum (frankS, 2026-08-31): the stale i386 sub-question is the SAME defect — and it settles the arena ticket's target scope

Re-measured the one claim this ticket still carried unverified, now that
`5454ef402` has landed. It reproduces, and then it turns out not to be this
ticket's at all.

**The i386-hosted compiler still faults building `compiler.pas` — 35.9s, natively,
no emulator.** That matches the 2026-08-30 reading ("~30s") closely enough to be
the same fault, so the stale claim was true; it just had no diagnosis.

`strace -e trace=mmap2` gives it in one run:

```
15 x mmap2(NULL, 268435456, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS)
   14 succeed: 0x1634b000, 0x2634b000, ... 0xe634b000  (exactly 0x10000000 apart)
    1 fails:   -1 ENOMEM
```

**Fourteen arenas succeed and the fifteenth returns ENOMEM — the same count, the
same size, the same unchecked-return death as frankA measured on arm32.** So this
is [[bug-a-the-arm32-hosted-compiler-wants-4x-the-arenas-and-dies-unchecked-at-enomem]],
not a separate i386 defect, and this ticket's last open sub-question closes by
being reassigned rather than by being answered.

**Three consequences, and the second is the one that matters for that ticket's
title.**

1. **It is not arm32.** i386 is the second 32-bit host to show it, so the appetite
   is 32-bit-wide. That ticket is named for arm32 and should not be.
2. **There is no emulator anywhere in this measurement.** i386 ELF executes
   natively on this box, so qemu cannot be a factor in the arena exhaustion at
   all — settled by execution rather than by argument, and without the arm32
   guest-core reasoning needing to carry it.
3. **The address space is genuinely full of arenas.** The fourteen are contiguous
   at exactly 256 MiB spacing from `0x1634b000` to `0xf634b000` — ~3.6 GB of a
   32-bit space. So on the map-versus-appetite question, the map is dense: this
   is not fragmentation leaving usable holes. Whether the arenas are full of
   *live* data is frankA's `bump` column, which this does not answer.

**Sibling check before closing, per CLAUDE.md.** `5454ef402` fixed arm32, riscv32
and xtensa. aarch64 already carried the guard on **both** directions
(`EmitLoadVarA64Dest` as well as `EmitStoreVarA64`; the load-side one is spelled
across several lines and a one-line grep misses it). x86-64 and i386 share an
emitter with no `EmitLoadVar`/`TypeSize` shape at all — they handle dynarray slots
at ~14 distinct sites explicitly — so the defect has no sibling there. **All
backends with the shape now have the guard.**
