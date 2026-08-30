---
slug: bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build
track: A+S
prio: 55
type: bug
blocked-by: []
resolved: f6660111e
status: working
found: 2026-08-30
found-by: frankS
owner: frankA
summary: "CLOSED by --xtensa-long-calls (option 2 of this ticket): the flag reserves the ~20-byte long form at every FORWARD internal call, so a callee past CALL0's 512 KiB is reachable. THE RESULT THAT MATTERS: `pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh --xtensa-long-calls compiler/compiler.pas` now BUILDS -- 24.4 MB, 3842 procs -- and that binary RUNS under qemu-xtensa and compiles test/hello.pas into a working program. Six of six cross targets now build the compiler. Off by default and the default path is proven byte-identical over 13 outputs on both ABIs. Option 1 (relaxation) stays OPEN as the right default and is re-filed as feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image; the per-body relaxation that closed the JUMP wall does NOT transfer, and the body of this ticket says why."
---

# A forward xtensa call over 512 KiB still cannot be built

Follow-up to
[[bug-a-xtensa-cannot-build-a-program-over-512-kib-of-code-call0-has-no-veneer]],
which closed the BACKWARD half. Read that ticket first: it explains the
long-call form (CALL0 leaves the following instruction's address in a0, so
target-minus-anchor is a relocation-free .text-offset delta) and why the
per-ABI scratch pair is a9/a10 under Call0 and a8/a9 under windowed.

## Why the forward direction is different

`EmitCallProc` widens a call whose body is already emitted, because the
displacement is known right there. A forward reference has no body yet: the site
writes a **three-byte placeholder** and records a `CallFix`, and by the time
`ApplyCallFixups` knows the target, the three bytes are surrounded by other
code. There is nowhere to put the other ~17 bytes.

## Measured

Generated program, 340 procedures, ~6.9 MB of xtensa code:

```
error: target xtensa: the forward call to __pxx_run_finalizers at code offset
142854 cannot reach its body at 6874588 (CALL0/CALL8 reach +-512 KiB). A
BACKWARD call this far is widened automatically; a forward one cannot be,
because the call site was sized before the body existed
```

That message is new — `ApplyCallFixups` now names the call and the direction
instead of leaving the bare encoder text. **`__pxx_run_finalizers` is the
tell**: an RTL routine emitted at the image tail, called from program
init/teardown near the front. Every xtensa image has that call, so the ceiling
is a property of the LAYOUT, not of unusual code — any program whose total code
exceeds roughly 512 KiB past that call site fails here.

The empty window this leaves is worth stating: a backward call out of range
needs >512 KiB between callee and caller, and the forward finalizer call caps
the image at ~667 KiB. The two walls nearly touch, which is why the five
programs in the parent ticket all failed backward and a synthetic large program
fails forward.

## Two ways to close it

1. **A relaxation pass.** Emit, and if any fixup is out of range, re-emit with
   forward calls widened. Correct and costs nothing on programs that fit; the
   work is making codegen re-runnable, which it is not today.
2. **`--xtensa-long-calls`** — every internal call takes the long form. Simple,
   uniformly larger and slower, and a complete answer for anyone who just needs
   the image to build. This is the parent ticket's option 2.

(2) is the cheap unblock and (1) is the right default; (2) is a reasonable
stepping stone since it also gives (1) its implementation.

**Either way this needs `defs.inc` and `compiler.pas`** (a flag, or a
re-emission driver) — both outside the Track S grant that closed the backward
half, which is why it is filed rather than continued.

## Do not reserve the long form unconditionally

The obvious third option — always reserve ~20 bytes at a forward call site — is
a real cost paid by every xtensa program, including the ones that fit inside
512 KiB, which is all of them today. The refusal is loud and correct; silent
bloat would be worse.

## Gate

The generated big-image repro above must build and run, and the 129-program
differential must be unchanged on both ABIs. If a flag is chosen, the default
path must stay byte-identical — verify by diffing emitted output against a
binary blessed before the change, since the self-host fixedpoint does not check
xtensa output at all.

## The wall directly behind this one (frankA, 2026-08-30 — measured to be MASKED, not absent)

riscv32's twin of this ticket is fixed
([[bug-a-riscv32-cannot-reach-a-far-call-so-the-compiler-will-not-link]],
`1df4ee490`), and the useful part for whoever takes this one is that the far
call was **not** what its repro was hitting. Two walls sat in series there, and
the same two are in series here:

1. the forward **call** (this ticket), and
2. the forward **jump to a label in the same body**, patched by the label fixup
   loop at the bottom of `IREmitMachineCodeXtensa` —
   `Patch24(pos, EncodeXtensaJ(LabelPositions[lblId] - pos))`, three bytes
   reserved before the target existed, **no long form and nowhere to put one**.
   J reaches ±128 KiB, four times tighter than riscv32's JAL, so a body needs
   only 128 KB to break it.

Measured, and the measurement is why this is a note rather than a ticket: a
generated single procedure of ~1 MB of code refuses at **this** ticket's error
first —

```
target xtensa: the forward call to __pxx_run_finalizers at code offset 143450
cannot reach its body at 1033672
```

— so (2) is unreachable today and cannot be given a repro of its own. **Expect
it to appear the moment (1) is fixed**, and file it then. The shape that closed
both on riscv32 is in `ir_codegen_riscv32.inc`: `Rv32JumpSlotBytes` /
`EmitRv32JumpToLabel` / `PatchRv32JumpSlot` — reserve the wide slot for a
forward jump, let the reach test pick the form at patch time, keep the cheap
form for every backward jump that reaches (80348 of 80399 in a 20 MB image).

## 2026-08-31 — this is now the last wall, and the jump half is a worked example

`pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh
compiler/compiler.pas` no longer fails on a jump. It fails here, and only here:

```
error: target xtensa: the forward call to __pxx_run_finalizers at code offset
144958 cannot reach its body at 24419736 (CALL0/CALL8 reach +-512 KiB)
```

**The jump half was fixed by RELAXATION and the same shape should work here**,
with one difference that has to be checked before anyone starts. A jump's
fixups are per-BODY, so re-emitting one body is a bounded operation with an
enumerable set of counters to restore (`IREmitMachineCodeXtensa` documents it).
Calls are patched by `ApplyCallFixups` at WHOLE-PROGRAM level, so the analogous
retry is "emit the whole image again", which is a different cost and a much
larger state surface — or, more likely, a per-body decision made from a
conservative estimate of where the target will land.

A **veneer pool** is more attractive here than it was for jumps: `CALL0` reaches
±512 KiB against `J`'s ±128 KiB, so a trampoline placed at the end of the calling
body — rather than at the image tail — is within reach of the call site in a way
the jump case could not manage. Not analysed further; noted so the next person
does not re-reject it on the jump ticket's reasoning, which does not transfer.

## Closed — `--xtensa-long-calls`, 2026-08-31 by frankA

**The goal, measured, and it is the whole point of the ticket:**

```
$ pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh \
    --xtensa-long-calls compiler/compiler.pas /tmp/pxx_xt
ok: /tmp/pxx_xt  [code=24465260B  data=463248B  bss=99157812B  procs=3842]

$ qemu-xtensa /tmp/pxx_xt --version
pxx (pascal26) — self-hosting Pascal-dialect compiler ...

$ qemu-xtensa /tmp/pxx_xt test/hello.pas /tmp/hello_by_xt
ok: /tmp/hello_by_xt  [code=61208B  data=2760B  bss=42452B  procs=129]
$ /tmp/hello_by_xt
Hello, World!
```

Not just "the image links": the xtensa-built compiler runs and compiles a
program that runs. **Claims discipline:** this is a cross build of the compiler
for xtensa, run under emulation. It is NOT an xtensa self-host fixedpoint and
nothing here claims one.

## Why option 1 (relaxation) was NOT used, and why the jump fix does not transfer

The forward JUMP wall was closed the same night by relaxation
([[bug-a-xtensa-cannot-widen-a-forward-jump-so-the-compiler-still-will-not-build]]):
emit the body, mark the labels whose three-byte slot did not reach, emit the
body again. **That works because a jump's fixups are per-BODY.** Re-emitting one
body is bounded, and the state it has to restore is a short enumerable list of
append-with-count arrays.

**A call's fixups are whole-PROGRAM.** `ApplyCallFixups` runs once, after every
body exists, so the analogous retry is *emit the image again* — and in this
compiler codegen is driven by the parser, so that is a second parse, not a
second walk. Different cost, different state surface, different design.

The note this ticket previously carried — that a veneer pool is more attractive
here than for jumps because CALL0 reaches four times further — still stands and
is untried.

## What the flag does

`EmitCallProc`'s forward arm reserves `EmitXtensaLongCallSlot` (the existing
long call, split at the point where it knew its target — same split as the jump
fix) and records the site in **the same `CallFix` list as every other call**,
distinguished by a new parallel `CallFixAnchor`: -1 is the ordinary three-byte
CALLn, anything else is the anchor PC of a long form whose literal is at
`CodePos`. `ApplyCallFixups` patches one or the other. One list, so `DceRun` and
any future consumer do not have to learn about a second.

The refusal now **names the flag**. A wall nobody can find the remedy for is
barely better than a wall, and the test row asserts the message names it.

## Gate, including the one this ticket asked for

- **Default path byte-identical**: 13 xtensa outputs (6 programs x both ABIs,
  plus a generated one) diffed between a control build with the change reverted
  and a build with it applied. Identical. The comparison was shown to be able to
  fail: the same `hello` with the flag ON is 223920 -> 228016 bytes.
- `make compiler/pascal26` converged 1 round; `tools/gate.sh quick` GREEN.
- The 13 xtensa jobs frankS's tstate report listed as red under the `a8`
  regression (`cce4a1ffb`) re-run here: 12 PASS. The 13th, `test_rtti`, prints
  raw pointer values and a 32-bit `InstanceSize`, so it cannot match an x86-64
  oracle and does not on `pinned` either — not a differential test, and not a
  row in `test-xtensa`.
- New `test-xtensa` row, both ABIs, with the refusal-names-the-flag control.

## Follow-up

`feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image` — option 1,
filed rather than left implicit, because a flag the user must know about is a
worse default than a compiler that widens what it must.
