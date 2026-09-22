---
slug: bug-a-two-code-to-code-references-are-unrecorded-and-are-safe-only-by-where-they-happen-to-sit
track: A
prio: 30
type: bug
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "NEITHER IS LIVE AND BOTH ARE LATENT FOR THE SAME REASON: they are safe because of WHERE they sit, not because anything checks. (1) exception_emit.inc:710 emits `xtensa_call8(ExcLongJmpAddr - CodeLen)` raw and records no CodeRef, where its riscv32 sibling at :510 goes through EmitRiscv32CallToCode and does record -- a policy divergence, not a considered exception. It is harmless today only because both endpoints are inside the runtime stub blob, which EmitProgramPrologue emits before any Procs[].BodyAddr exists, so DceOwnerOf answers -1 there and DCE never moves the distance between them. (2) IREmitCodeCall (ir_codegen.inc) has arms for arm32 and aarch64 and then an UNGUARDED x86 tail -- no riscv32 or xtensa arm, so either of those targets reaching it emits `E8 rel32` into a body. Safe today only because every caller reachable on those targets happens to be behind an explicit TargetArch test, which is a property of ~60 call sites and not of the function. A new caller added to a shared *ForTarget routine breaks it silently. Fix (2) by making the tail REFUSE on riscv32/xtensa rather than fall through; fix (1) by routing it through EmitXtensaCallToCode like its sibling."
---

# Two code-to-code references are unrecorded, and are safe only by where they sit

Found 2026-09-20 while answering
[[bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program]]. Both
were verified by reading the code, not taken from a report. **Neither is a live
defect and both are filed anyway**, because the thing that makes each safe is
an accident of placement that nothing asserts.

## (1) `exception_emit.inc:710` — the xtensa tail call into `ExcLongJmp`

```pascal
xtensa_call8(ExcLongJmpAddr - CodeLen);            { never returns here }
```

Its riscv32 sibling, `exception_emit.inc:510`, is the identical construct and
**is** recorded:

```pascal
EmitRiscv32CallToCode(reg_zero, ExcLongJmpAddr);   { tail jump, never returns }
```

This is the "normalise, don't special-case" sibling problem in its usual
spelling: the same meaning reached through two constructs, one of which was
updated when CodeRef recording landed and one of which was not.

**Why it is not firing.** Both endpoints live inside the runtime stub blob that
`EmitProgramPrologue` emits *before* any procedure body. `DceOwnerOf` returns
−1 there, `DceCollectBodies` never puts that range in `DceOrder`, and
`DceRemStart`/`DceRemEnd` only ever cover body ranges — so the byte distance
between any two points in the blob is invariant under DCE.

**What would make it fire:** anything in that blob becoming a `Procs[]` row, or
DCE learning to compact the blob. `symtab.inc`'s own note near
`EmitRiscv32CallToCode` says the equivalent thing came true once already.

Note the third sibling deliberately left alone: `exception_emit.inc:638`'s
self-recursive `xtensa_call8(ExcSpillAddr - CodeLen)` is raw ON PURPOSE, and
the reason is stated above it — a helper that might widen would make the
hand-computed `beq` skip distance on the next line a guess. **Do not "fix" that
one by symmetry with this one.**

## (2) `IREmitCodeCall` falls through to x86

`ir_codegen.inc`'s `IREmitCodeCall` has an arm32 arm, an aarch64 arm, and then
an unguarded tail:

```pascal
  EmitB($E8);
  RecordCodeRef(addr);
  EmitI32(addr - (CodeLen + 4));
```

There is no riscv32 or xtensa arm. On either of those targets, reaching this
function emits an x86 `call rel32` into the instruction stream.

**Why it is not firing.** Every caller reachable on riscv32/xtensa is behind an
explicit `if TargetArch = ...` test; the rest live inside the x86-64 backend or
target `*Addr` variables only x86-64 emitters ever set, so the function's own
`addr = 0` guard fires first. **That is a property of roughly sixty call sites,
and it is re-established every time someone adds one.**

**The fix is the cheap direction:** make the tail refuse —
`Error('compiler error: IREmitCodeCall has no arm for this target')` — rather
than encode x86. A routine whose terminal arm is "assume x86" in a compiler
with seven backends is a default colliding with a plausible answer: the bytes
it emits are valid x86 and mean nothing on the target, so the failure is a
wrong instruction stream rather than a diagnostic.

The precedent is already in the tree: `HeapMmap`'s terminal arm returns a
defined failure value with a written-out argument for why it is not `{$error}`
(it is compiled everywhere and called almost nowhere). `IREmitCodeCall` is the
opposite case — it is only ever reached deliberately — so a refusal is right.

## What would retire this ticket

Both sites changed, plus a guard on (2) that a riscv32 or xtensa build reaching
`IREmitCodeCall` fails loudly. **The guard needs a positive control that is
hard here and should be said out loud rather than skipped:** there is currently
no caller that reaches it on those targets, so the refusal cannot be exercised
without adding one. A temporary call behind a debug flag, asserted to refuse,
is the honest way; a guard nothing can trip is the thing this repo files
tickets about.

## 2026-09-22 (frankb-8e) — BOTH FIXED, AND THE PRESCRIPTION FOR (1) NAMED THE WRONG HELPER

Taken as the group neighbour of
[[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]], whose own
blocker turned out to be a THIRD member of this family — `EmitCodeAbsToRdx`,
unrecorded, and unlike these two it was LIVE. Three instances of one mechanism,
one commit each.

**(2) — the unguarded tail now refuses.** `IREmitCodeCall`'s fall-through emits
`E8 rel32`, so riscv32 and xtensa reaching it wrote an x86 instruction onto a
target that has no such opcode, silently. It now `Error`s on those two and
names the two helpers that exist (`EmitRiscv32CallToCode`,
`EmitXtensaCallToCode` / `EmitXtensaCall8ToCode`), so whoever adds the caller
this ticket predicts gets a one-line answer instead of a wild branch.

**NOT BORN RED, and that was checked rather than assumed** — the population is
"everything on those two targets that owns a `*Addr` caller":
`test_cross_exception`, `test_exception_finally` on riscv32; those plus
`test_esp_bare`, `test_esp_exception` on xtensa; bare and `--platform=posix`;
`--no-dce` and `--dce`. All build rc=0.

**(1) — routed through `EmitXtensaCall8ToCode`, NOT `EmitXtensaCallToCode`, and
the difference is a live bug rather than a detail.** The prescription in the
summary above names the CALL0 helper. `ExcLongJmpAddr`'s windowed stub is
entered with `{ a2 = &jmpbuf }` and ends in **RETW**, and the site reaches it by
loading **a10** — the CALL8 argument register, which a window rotation of 8
makes the callee's a2. Under CALL0 nothing rotates: the callee would read the
caller's own a2 (the raw handler frame, not `frame + EXC_JMP_OFFSET_XTW`) and
then `retw` with no window under it. `EmitXtensaCall8ToCode`'s own header says
this in advance — *"NOT a windowed arm inside EmitXtensaCallToCode, which would
have been the smaller diff and would have been wrong"* — so the correction was
available at the point of prescribing. **A prescription in a summary reads as a
requirement and is a claim to check**; this one was written from the riscv32
sibling, where there is only one helper and so no choice to get wrong.

**AND (1) HAD A SECOND HALF THE TICKET DID NOT SEE, WHICH IS WHY FIXING IT AS
WRITTEN WOULD HAVE CONVERTED A LATENT BUG INTO A LIVE ONE.** The branch above
the call was `xtensa_beq(a2, a4, 9)` — a HARDCODED displacement counting
3 (beq) + 3 (addi) + 3 (call8). `EmitXtensaCall8ToCode` widens to a literal
slot when the target is out of reach, and that 9 would then land inside the
widened call. The five sibling arms of this same procedure (x86-64 :153 and
:303, arm32 :368, aarch64, riscv32 :507) all patch from `CodeLen`; the xtensa
arm was the only one of six counting bytes. It patches from `CodeLen` now.

**The control, and the first one I ran was wrong in a way worth recording.**
Output must be byte-identical wherever the call stays short, because the
patched displacement recomputes to the same 9. I measured that first on
`--target=xtensa --platform=posix` — IDENTICAL on four builds — and it proved
nothing: that route takes the **Call0** arm at :535, not the windowed one at
:579. A one-line `Error` probe inserted into the arm showed it is reached only
with `--xtensa-abi=windowed` (and that `--esp-profile=bare` REFUSES that ABI
outright, so no bare build can reach it either). Re-run on the right route —
`--target=xtensa --platform=posix --xtensa-abi=windowed --xtensa-soft-mulhigh`,
two sources × `--no-dce`/`--dce` — all four IDENTICAL. **Isolation guards the
run, not the route**, and the wrong-route control was current, correctly
parameterised, and honest.

What the byte-identical result does NOT show is that the CodeRef is now
recorded — identical bytes are also what "nothing happened" looks like. That is
carried by the probe (the arm runs) plus the helper being unconditional in
recording; and the identity is itself the evidence that DCE was not moving this
distance, which is exactly the "safe by where it sits" this ticket filed.

Tree: `fd6965890102`.
