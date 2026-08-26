---
prio: 70
status: done
owner: frank1-N-reds
---

> **origin/dev has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-uforth#core red at 44193e547f6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T20:32:52Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'test-uforth#core'` at 44193e547f6d4ca77453770378b710d8af82f5df

## Range
bad `44193e547f6d`, last good `d2cb6721e175`, 23 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
compiling uforth.py as Nil-Python ...
test-uforth: smoke PASS — compiles, STD.UFO loads, native + PYTHON-bodied words evaluate
running uforth's own corpora, DIFFERENTIAL against CPython ...
running the Forth 2012 / ANS suite per WORD SET, DIFFERENTIAL against CPython ...
Segmentation fault
  DIFF word set core.fr
--- /tmp/tmp.hxQXtvnruM/c.out	2026-08-25 22:30:46.277170989 +0200
+++ /tmp/tmp.hxQXtvnruM/p.out	2026-08-25 22:30:48.522210682 +0200
@@ -41,27 +41,4 @@
 
 Test utilities loaded
 
-*********************YOU SHOULD SEE THE STANDARD GRAPHIC CHARACTERS:
- !"#$%&'()*+,-./0123456789:;<=>?@
-ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`
-abcdefghijklmnopqrstuvwxyz{|}~
-YOU SHOULD SEE 0-9 SEPARATED BY A SPACE:
-0 1 2 3 4 5 6 7 8 9 
test-uforth: FAIL — 1 of 1 corpora differ from CPython

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

---

## RESOLVED — root cause, and what the corrected range was worth (Track N, frank1-N-reds, 2026-08-26)

**Reproduced at HEAD, deterministically.** `make test-uforth`'s `core.fr` word
set dies with SIGSEGV inside `TESTING DEFINING WORDS: : ; CONSTANT VARIABLE
CREATE DOES> >BODY`. Narrowed inside that section to five lines, then to two,
then out of the harness entirely:

```
: WEIRD: CREATE DOES> 1 + DOES> 2 + ;
WEIRD: W1
W1 .          <- SIGSEGV; CPython prints 65538 and exits 0
```

The DOUBLE `DOES>` is the whole shape. A single `DOES>` (the `DOES1`/`DOES2`
cases 30 lines above) is fine.

### The range mattered, and the filed one would have convicted an innocent commit

The culprit is **`293d70509` "fix(N): a bare def name in value position is boxed
like every other callable"**, and `git merge-base --is-ancestor 293d70509
d2cb6721e175` is TRUE — it is an ancestor of the last-good sha this ticket was
filed with, i.e. it lies in the 156 commits the 23-commit window excluded. That
window could not have contained it.

This is not hypothetical: the watcher's own idle bisect ran over the filed range
and converged, in four steps, on **`ab584382edcd` — "tickets: apply the approved
re-triage"**, a commit whose entire diff is 250 `prio:` lines in ticket
frontmatter. It touches no code at all, and the same sha was reported as the
single culprit for four unrelated jobs. That is exactly the failure mode the
annotation warned about, observed.

Endpoints proven by measurement rather than assumed: the PINNED stable binary
(v374, `a687bb877`, which carries its own frozen `compiler/builtin/`) compiles a
uforth that runs the repro clean; HEAD's does not. Reverting `293d70509`'s
`compiler/pyparser.inc` hunk alone and rebuilding the compiler turned both this
red AND `regression-test-nilpy-test-nilpy-type-name-of-a-big-int` green — one
commit, two reds.

Also ruled out by measurement before bisecting: HEAD compiler + v374's frozen
RTL still crashes, so the fault was in the compiler, not the RTL. Only 4 commits
touched `pyparser.inc` in the whole honest range.

### Root cause — the invoker does not own the callable while it runs

uforth's `w_does` builds `does_runtime(vm2, _addr=..., _dw=does_word)` — a
nested def whose captures are DEFAULT ARGUMENTS, so a lifted bound-fn (variant
tag 10) — and stores it in `target.native`. With two `DOES>` in one definition,
the does-body of `W1` contains a second `DOES>`, so running `W1` reaches
`w_does` again with `target` still `W1`, and `target.native = does_runtime2`
**overwrites the very slot holding the closure that is on the stack**.

`w.native(self)` lowers to a dynamic call that takes the callee `const` — it is
BORROWED. The attribute was the only strong reference, so the assignment
released the running closure to rc 0, freed it, and the free cascaded into the
`Word` it had captured as `_dw`; `run_forth_word`'s `finally` then read
`word.name` out of the freed block.

Measured, not reasoned:
- `-dPXX_HEAP_DEBUG` moved the crash EARLIER and put `0xdddddddddddddddd` in
  `rax` at the faulting `incq -0x10(%rax)` — a RETAIN of a pointer read out of
  freed memory, which is the signature of a use-after-free rather than a wild
  pointer.
- `-dPXX_OBJTRACE` showed the exact cascade: `r <closure> 0` / `F <closure>`
  immediately after the second closure is boxed, then `F` on the captured Word
  and on what the Word owned, then the fault.
- `addr2line` put the outer frame at `uforth.py:1629`, `VM.run_forth_word`'s
  `finally`.

`293d70509` did not introduce the borrow. It removed the LEAK that had been
masking it: the old value-position arm handed back an unmanaged `tyPointer`
whose never-released reference kept every such closure alive forever. The
commit is right; the borrow underneath it was always wrong.

### Fix

State the ownership once per callable ROAD, at the funnel each road already
has, rather than at the dozen call sites that reach them:

- `compiler/builtin/pyeval.pas` — `pyboundfn_callvn_mask`, the funnel every
  lifted bound-fn (tag 10) invocation passes through, is now a
  retain/try/finally/release wrapper over the renamed body.
- `compiler/builtin/pylib.pas` — `pybound_pair_call_kw`, the same for every
  `{code, recv}` pair (tag 8).

`PXXObjRetain`/`PXXObjRelease` are magic-guarded, so a plain code address or a
static RTTI blob no-ops through both. That covers `pyvar_callv0..4`,
`pyvar_callv_kw`, `pybound_callv0..4`, `pycallback_call0/1` and the `*_call_ptr`
field fast paths in two edits.

Sibling check (`normalise-dont-special-case.md`): `PyCallableStr` /
`PyCallablePartsP` already answered bound-vs-plain from the RECEIVER rather than
the tag (`4eb11a20b`). The arm that had not been updated was the type-NAME
table, which is the other red — fixed with it.

### Verification

- `core.fr` differential against CPython: **IDENTICAL**, both exit 0.
- New regression test `test/test_nilpy_callable_replaces_its_own_slot.npy` —
  the reduced shape plus the tag-8 and bound-method variants of the same hazard.
  Confirmed to SEGFAULT with the fix reverted and to match CPython with it.
- `make compiler/pascal26` fixedpoint, `tools/gate.sh quick`.
- 2026-08-26 — resolved, commit PENDING-COMMIT.
