---
prio: 70
track: A
status: done
owner: frank1-A-aarch64
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/dev has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_forin_member_access.pas red at 44193e547f6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T20:32:52Z
- **Test source:** test/test_forin_member_access.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_forin_member_access.pas'` at 44193e547f6d4ca77453770378b710d8af82f5df

## Range
bad `44193e547f6d`, last good `d2cb6721e175`, 23 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2553870/test_aarch64_fima  [code=152328B  data=3040B  bss=42368B  procs=130]
ok: /tmp/testmgr-scratch-2553870/test_aarch64_fima_x64  [code=65652B  data=3088B  bss=42504B  procs=130]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## CORRECTION — the range above is WRONG, and too narrow (Track T, 2026-08-25)

**Do not bisect the 23-commit range this ticket was filed with.** The job named
here does not run in the `native` tier, and the parent it was diffed against
(`d2cb6721e175`) was a native run. It last actually executed in the full tier at
`aa9f0989a4c0` on 2026-08-24 — so the honest range is **179 commits**
(`aa9f0989a4c0..44193e547f6d`), not 23, and the last-good sha is
`aa9f0989a4c0`, not `d2cb6721e175`.

This matters more than the arithmetic suggests. A bisect over a range that does
not contain the culprit does not fail and does not report "not found" — it
narrows, confidently, onto an innocent commit, and a core-job red is a revert
candidate by this repo's own rule. The 23-commit window is precisely the set of
commits that CANNOT have caused this, since the job was already in this state
before the window opened.

Cause: `twatch` computed the blame range from "since this host last tested
anything" rather than "since this job last ran". Fixed in `c68e6492e` —
the range is now decided per job from `job_tier` and widened only when the
parent's run provably did not contain it. Tickets filed from later runs carry
the corrected range; this one is annotated rather than rewritten, because the
filed text is the record of what the watcher actually claimed.


## ROOT CAUSE — not aarch64, not the code size (frank1-A-aarch64, 2026-08-26)

**Not a backend bug, and the code-size difference in the log tail is a red
herring.** The two `ok:` lines are the aarch64 build and the x86-64 build of the
*same* source — 152328B vs 65652B is aarch64's fixed-width encoding against
x86-64's variable-length one, which is what that ratio always looks like here.
The IR is byte-identical between the two targets (`PXXDBG=a.ir:TGame.SumIds`,
diffed); nothing about this was backend-local.

**The bug:** `for x in <member access>` does not iterate the container in place.
`ParseForInNodeAST` materialises it into a HIDDEN dyn-array local
(`fnSym := AllocDynArray('', ...)`), so the container is evaluated exactly once,
and drives the ordinary bare-variable loop with that. The hidden local is minted
*while the body is being parsed* — after `EmitManagedLocalsZeroInit` has already
run in the prologue — so it was never zero-initialised. The loop's first
`IR_STORE_SYM` into it does the normal managed publish: retain new, store,
**release old** — and "old" was whatever the frame happened to hold.

When those bytes were a live heap pointer, that decremented a refcount nobody
owned. In `test_forin_member_access` the victim was the second TItem, whose
`Id` sat exactly where `PXXHdrRC` looked, so `30 + 12` printed 41. A silently
decremented field, one indirection away from the loop, on a target chosen by
frame layout — the "plausible wrong value far from the cause" case.

**It is not aarch64-specific.** With a routine in front of the call that leaves a
live pointer in the slot, x86-64, i386, aarch64, arm32 and riscv32 all print the
same wrong answer, at -O0 and -O2. aarch64 was simply the only target whose
natural frame layout put a live pointer there for *this* test. Measured against
a self-hosted pre-fix build of `origin/dev`:

```
pre-fix, test_forin_member_temp_zeroinit (frame dirtied on purpose)
  x86_64 3102 | i386 7692 | aarch64 3102 | arm32 7692 | riscv32 7692
pre-fix, test_forin_member_access (frame NOT dirtied)
  x86_64 42 | i386 42 | aarch64 41 | arm32 42 | riscv32 42   <- the filed red
```

**The 179-commit range did not matter** and no bisect was run. Endpoint
measurement plus shape variation found it in one pass, which is the cheaper
route the ticket's own correction note recommends.

### The design flaw behind it

"A managed local minted after the prologue must start nil" had SEVEN partial
owners, and the for-in container temp was covered by none:

1. the prologue's `EmitManagedLocalsZeroInit` — declared locals only;
2-7. one `SymIsHiddenArgTemp` walker per backend — flagged temps only, and the
   flag is not set on this one;
8. an x86-64-only "safety net" for unnamed temps the flag missed — and it was
   scoped `not IsArray` AnsiString/Variant, so a dyn ARRAY temp slipped past
   even the net, on the one target that had a net at all.

**Fix (`e871478ab`):** split the "which kinds are managed, and how far do they
reach" table out of `EmitManagedLocalsZeroInit` as `ManagedLocalZeroBytes`, and
give `CompileAST` a late-mint pass that asks it the same question for every
unnamed managed `skLocal` the body's parse/lowering minted — replacing the
COM-interface-only scoping that stood there. One table, every kind, every target.

### Follow-up left on the table

Folding the six per-backend flagged walkers into that one pass was tried
(`d549ce524`) and **reverted** (`4dd1fa397`): it self-hosted and passed this
bug's cross-target repro, then segfaulted `quick_canary_nilpy` and every
promo-int test. The two tables disagree in ways worth measuring before trying
again — the walker zeroes a flagged temp of ANY kind while `ManagedLocalZeroBytes`
answers 0 for kinds it does not consider managed; and the walker emits inline
stores while `EmitZeroFrameSlot` routes anything wider than a pointer to a CALL
to `PXXMemZero`, which a promo slot (16 bytes) always crosses. The revert commit
carries the full note.

Cost of not doing it: none, in the end. The late-mint pass now SKIPS flagged
temps (`4427e6855`) rather than duplicating the backends' stores — leaving them
in doubled every such slot, +112 KB / +1.2% on the compiler's own code. With the
skip the compiler comes out at 9123569 bytes against 9124696 before the fix, i.e.
1127 bytes SMALLER, because the unnamed unflagged temps the x86-64 safety net
already nil'd now go through EmitZeroFrameSlot's single-store path. So the
remaining duplication is only conceptual (two tables, one flagged half and one
unflagged), not paid for in emitted bytes.

### Gate
`make compiler/pascal26` converged (self-host fixedpoint) · `tools/gate.sh quick`
· the repro on x86-64 / i386 / aarch64 / arm32 / riscv32 at -O0 and -O2 · the
aarch64 cross target, both `test_forin_member_access` and the new
`test_forin_member_temp_zeroinit`, against their x86-64 differential partners.

### Regression tests
Two, both wired into `test-core` and into the i386 / aarch64 / arm32 / riscv32
cross lists, and both verified to fail against a self-hosted PRE-FIX build:

- `test/test_forin_member_temp_zeroinit.pas` — the filed shape with a
  frame-dirtying call in front, so the witness does not depend on a target's
  accidental frame layout. Pre-fix: 3102 / 7692 on all five targets.
- `test/test_hidden_dynarray_temp_zeroinit.pas` — the SIBLINGS. Grepping before
  closing (per `normalise-dont-special-case.md`) found three more mint sites for
  the same unnamed dyn-array temp: `for x in MakeArr` and `for x in [a, b]`
  (`pasparser_stmt.inc`) and `MakeArr[0]` (`pasparser_lval.inc`,
  `ApplyCallResultPtrSuffix`). All three carry the identical hazard and all three
  are fixed by the one shared pass — which is the argument for having fixed it
  there rather than in `ParseForInNodeAST`. Pre-fix this one SIGSEGVs on
  x86-64, i386, aarch64, arm32 AND riscv32, so it is a crash witness, not a
  wrong-answer one.
- 2026-08-26 — resolved, commit e871478ab (the fix) + 4427e6855 (no double zeroing); tests be728cc06, 1d91a37ab; refactor attempt d549ce524 reverted by 4dd1fa397.
