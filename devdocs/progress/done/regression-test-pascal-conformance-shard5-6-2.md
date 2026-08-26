---
prio: 70
status: done
owner: frank1-P-conf
---

> **origin/dev has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard5/6 red at 44193e547f6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T20:32:52Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard5/6'` at 44193e547f6d4ca77453770378b710d8af82f5df

## Range
bad `44193e547f6d`, last good `d2cb6721e175`, 23 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tdefault8.pp — compile error:
pascal26:27: error: incompatible types: cannot assign Int64 to record
(tail)
specialize G<T>.Create as expression/procvar)
SKIP tgeneric15.pp — gap: class inheriting from `specialize TStack<Integer>` as parent type
SKIP tgeneric20.pp — wontfix: dialect-pass — generic method impl without <T> marker — PXX's generics surface deliberately accepts the stripped form (3d71edcf); not a bug
SKIP tgeneric26.pp — gap: accepts-invalid — type parameter in a variant part must be rejected (substitution model has no pre-specialization check)
SKIP tgeneric48.pp — gap: mixed generic overloads by arity (class/record/interface/procvar/array)
SKIP tgeneric59.pp — gap: same generic name with different arity (TTest<T> vs TTest<T,S>) in delphi mode
SKIP tgeneric6.pp — gap: objfpc generic syntax + nested record/pointer types inside a generic class
SKIP tgeneric91.pp — gap: Self in class procedure of a generic class specialized cross-unit
SKIP tgeneric97.pp — wontfix: expects FPC's internal specialized ClassName 'ttest<system.longint>'
SKIP tgenfunc12.pp — gap: generic methods with class/interface constraints and generic global functions
SKIP tgenfunc4.pp — gap: delphi-mode generic class function with inline type args
SKIP tmoperator7.pp — gap: management operators inside object/dynarray of records + class var
SKIP toperator6.pp — gap: `operator :=` implicit-conversion overload + qword/int64 overload selection
SKIP toperator91.pp — gap: class operators Explicit/Implicit overloaded on ShortString[N] result types
SKIP tprocvar2.pp — gap: typed const procvar initialized with bare proc name (TP mode), procvar via move()
SKIP tsetsize.pp — wontfix: asserts FPC's exact set-size/packing layout (SizeOf(set of subrange))
SKIP tstring10.pp — gap: punicodechar/pwidechar value casts + unicodestring/widestring conversions (Flush/Output landed)
SKIP tstring5.pp — gap: RTL `ExitCode` variable missing (needed by testsuite erroru unit); ansistring compares
test-pascal-conformance: 55 pass, 1 fail, 28 skip, 7 auto-gated (of 91)
test-pascal-conformance: FAILURES: tdefault8.pp(compile)

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

## It is NOT the harness ticket — ruled out by shape (coordinator, 2026-08-26)

Worth stating up front because the obvious first move is to blame
`bug-t-run-pascal-conformance-silently-fails-every-test-on-a-relative-compiler-path`,
and that would cost an afternoon of archaeology before ruling it out.

That bug fails **every** test in **every** shard when it fires: the runner `cd`s
into the suite dir and a relative `$CC` stops resolving for all of them at once.
Across both completed breadth runs, shards 0-4 PASS and only `shard5/6` is red.
A harness fault cannot be that selective. So this is a genuine conformance
divergence and it belongs to Track P.

**Reproducible, not a flake.** Two completed full tiers now:
`44193e547f6d` (wall 2492s of 7200) and `8f403875d51a` (wall 2285s), the second
with **zero NEW-RED and zero FIXED** and the same five STILL-RED. Nothing in the
commits between them changed the picture, which is exactly what a second breadth
run is for.

**Trap in the report text, read this before diagnosing.** The reason field shows
two `SKIP` lines -- `tprocvar2.pp` and `tsetsize.pp`. Those are the **truncated
head of the shard output**, not the failure, and reading them as the cause sends
you after two tests that are being skipped on purpose. The failing test name is
further down in the job log. Get from "the shard is red" to "this named case is
red" from the log itself before forming any theory.

And the blame range on this stub is **179 commits**, not the 23 it was filed
with -- see the Track T annotation above. `test-pascal-conformance` does not run
in the native tier, so the narrow window is precisely the set of commits that
cannot have caused this.

## The runner is fixed — run it by hand and trust what you see (2026-08-26)

`bug-t-run-pascal-conformance-silently-fails-every-test-on-a-relative-compiler-path`
is **resolved** (`bc0ffebf9`). This matters to whoever takes this ticket because
it sat directly in the path: the first thing anyone does is run the runner by
hand, and the natural spelling is
`tools/run_pascal_conformance.sh ./compiler/pascal26 ...`.

Before that fix, the relative spelling gave **10 pass / 51 fail**, every failure
reported as `compile error` — a wall of red that looks exactly like "my change
broke the compiler", arriving at the precise moment you are looking for what
your change broke. Relative and absolute now agree exactly: 62 pass, 0 fail,
42 skip either way.

So a red you see by hand is now a real red. Get from "the shard is red" to
"this named case is red" from the job log — and remember the two `SKIP` lines in
the report reason are the truncated HEAD of the output, not the failure.

## RESOLVED — one named case, and it was never a regression (Track P, 2026-08-26)

**The red case is `tdefault8.pp`, and it is the only one.** It was already in
the filed log tail (`FAILURES: tdefault8.pp(compile)`) — the two `SKIP` lines in
the report *reason* field are the truncated head of the shard output, as the
coordinator's note warned. Reading the log rather than the reason gets you there
in one step.

```
pascal26:27: error: incompatible types: cannot assign Int64 to record
```
line 27 is `trec := Default(TTest.TRecord);`.

### What it actually was

`Default()` carries a hand-rolled type dispatch that keys on the **bare leading
token**. Given `Default(TTest.TRecord)` it asked `IsRecordType('TTest')` — TTest
is a class, so REC_NONE — missed the aggregate arm entirely and fell through to
the integer-zero arm, producing an **Int64 where a record belonged**.

### Regression or latent? LATENT — and the type check is the hero, not the culprit

Endpoint measurement, not bisection (per the playbook's new section):

| binary | `Default(TTest.TRecord)` |
| --- | --- |
| `stable_linux_amd64/default/pinned` | compiles clean, **SEGFAULTS at runtime** |
| HEAD | rejected at compile time |

`tdefault8.pp` is `{ %NORUN }` — compile-only — so the conformance suite only
ever *typed* it, and the type it had was wrong in a way nothing looked at. The
bug is as old as `Default()`'s dispatch. What changed is that assignment
type-checking landed and made a latent crash visible, which is exactly what it
is for. The `Default()` code's own comment predicted this failure mode
(`bug-p-default-of-a-record-segfaults-of-an-array-does-nothing`) — it fixed the
UNQUALIFIED arm and the qualified one kept the old behaviour.

**So the 179-commit range did not matter.** Neither would the 23. There is no
culprit commit to find: a bisect over any window would have converged on
whichever commit turned the type check on and named a *correct* commit as the
cause — the precise failure mode the playbook section describes. Pinned-vs-HEAD
took one command.

### Not a divergence — FPC accepts it

FPC 3.2.2 compiles `tdefault8.pp` with three "assigned but never used" notes and
no errors. Nothing goes in `pxx.skip`.

### The double case, and the sibling grep

The rule `Default()` was missing already existed **twice**: `var r:
TTest.TRecord` has it in `ParseTypeKind`, and `SizeOf(TTest.TRecord)` grew its
own inline copy (with a comment saying a half-working feature is worse than an
absent one). `Default()` is the third construct with a bare-token dispatch and
the only one that never learned it — the second path is the one that stays
broken.

Fix = one resolver, `ScanNestedTypeRun` (`pasparser_class.inc`), called by
`Default()`. It **scans without consuming**, because the caller must decide
before it commits: a nested *record* has to be taken through the registry
scope-correctly, while a nested subrange, enum or array is not a UClass row at
all and belongs to `ParseTypeKind`'s own strip.

Grep boundary, stated because it bit: a fourth site
(`pasparser_expr.inc`, the `TOuter.TInner.Create` walk) open-codes the same walk
under different names (`nestScanCi`/`nestScanPos`) and requires a trailing
`Create`. It is a genuinely different shape and is left alone. **`SizeOf`'s
inline copy IS folded onto `ScanNestedTypeRun`** (second commit) — two copies of
the rule is not incidental to this bug, it is the mechanism by which the third
construct went without it. Pure dedup, no behaviour change, verified by holding
the scope-blind widths still.

### Verified against the FPC oracle

Four shapes, pxx vs FPC 3.2.2, agreeing exactly:

- class-nested record — `Default(TTest.TRecord)`
- doubly nested — `Default(TThree.TMid.TLeaf)`
- record owner — `Default(TRecOwner.TInner)` (FPC needs `advancedrecords`; pxx
  answer is self-consistent)
- **same-named nested type in two owners** — `TA.TSub` (4 bytes) and `TB.TSub`
  (32 bytes) both zero their own width; the flat lookup would have answered with
  whichever registered first

Plus the runtime probe that segfaulted under pinned now prints `f=0`.

### Gate

`make compiler/pascal26` (converged in 1 round — byte-identical self-host
fixedpoint), the individual `tdefault*` cases (12 pass / 0 fail), the whole
shard 5/6 (**55 pass / 1 fail -> 56 pass / 0 fail**), and `tools/gate.sh quick`.
- 2026-08-26 — resolved, commit PENDING-COMMIT.
