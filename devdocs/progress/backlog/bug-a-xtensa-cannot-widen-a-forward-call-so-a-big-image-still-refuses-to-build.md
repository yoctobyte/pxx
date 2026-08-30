---
slug: bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build
track: A+S
prio: 40
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
owner: unassigned
summary: "The backward half of the CALL0 reach wall is closed (a call to an already-emitted body is widened automatically). A FORWARD call cannot be: EmitCallProc reserved three bytes before the target existed, so ApplyCallFixups can only refuse. Measured on a generated 6.9 MB image: the forward call to __pxx_run_finalizers at code offset 142854 cannot reach its body at 6874588. An RTL routine at the image tail called from early code is structural for any large xtensa program."
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
