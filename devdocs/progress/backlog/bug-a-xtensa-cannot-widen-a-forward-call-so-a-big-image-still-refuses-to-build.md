---
slug: bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build
track: A+S
prio: 55
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
owner: unassigned
summary: "The backward half of the CALL0 reach wall is closed (a call to an already-emitted body is widened automatically). A FORWARD call cannot be: EmitCallProc reserved three bytes before the target existed, so ApplyCallFixups can only refuse. Measured on a generated 6.9 MB image: the forward call to __pxx_run_finalizers at code offset 142854 cannot reach its body at 6874588. An RTL routine at the image tail called from early code is structural for any large xtensa program. RE-RANKED 40 -> 55 on 2026-08-31: with the forward JUMP wall closed (bug-a-xtensa-cannot-widen-a-forward-jump-...) this is now the SINGLE remaining wall between xtensa and building the compiler. Measured at that commit: `pascal26 --target=xtensa compiler/compiler.pas` gets past every jump and stops here -- forward call to __pxx_run_finalizers at 144958, body at 24419736."
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
