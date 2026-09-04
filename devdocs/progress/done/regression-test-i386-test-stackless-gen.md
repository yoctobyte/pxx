---
prio: 70
track: A
status: done
---

> **Track A from the job NAME `test-i386`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_stackless_gen.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-i386#src:test/test_stackless_gen.pas at cf9b14600039 in step 2/3, `./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_i386_slg_x64` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T07:41:43Z
- **Test source:** test/test_stackless_gen.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 3 of the job's recipe; it names `test/test_stackless_gen.pas`.
  ```
  ./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_i386_slg_x64
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-i386#src:test/test_stackless_gen.pas'` at cf9b14600039c2f62d7251b0e05330fb74827be9

## Range
> **The named sha `cf9b14600039` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cf9b14600039`, last good `e7a805d13a09`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:144: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
(tail)
ok: /tmp/testmgr-scratch-2655869/test_i386_slg  [code=180076B  data=5000B  bss=42396B  procs=259]
pascal26:144: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
  near: , ' ' ) ; writeln ; >>> end . unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Resolved 2026-09-04 by frankb-78 — mine, and the red list pointed the wrong way

**Cause: `7e271ff7d`** (the for-in generator teardown fix). Fixed in the commit
that lands beside this note; all four targets now match the expected output.

**It was never a cross-target defect.** `test_stackless_gen.pas` does not
COMPILE on x86-64 at `7e271ff7d` either:

```
compiler error: call to a runtime stub that was never emitted
(code offset 0 is the ELF entry point)
```

The three rows that reported are the ones that diff a cross run against an
x86-64 oracle; the host's own row was not in what the report listed. So
**"x86-64 is not among them" was a true fact that reads as evidence for a
width- or target-dependent cause, and the cause was universal.** That is the
mirror of the i386-invisibility rule: a red list without the host can mean the
host is fine, or that the host's row was never printed.

**Mechanism.** `EmitExceptionRuntime` writes CODE and the stubs must precede
the body, so the decision is a token PRE-SCAN in `ParseProgram` looking for a
source `try`/`raise`. The new desugar synthesises a try/finally, so a program
with no `try` of its own got `ExcRaiseAddr = 0`. `IREmitCodeCall`'s guard turned
that into a compiler error rather than the infinite entry-point loop it
describes — that guard is the only reason this was loud.

Calling `EnableExceptionRuntime` from the desugar builds cleanly and
**segfaults**: the stub bytes land inside the body already being emitted. Both
states were measured before the right one was found.

**The prescan already had this arm for `class operator Finalize`**, with a
comment describing this failure almost word for word. A third synthesised-try
site was added without grepping for the second — the literal stated form of
`normalise-dont-special-case`. And the SECOND sibling was already broken: the
class-enumerator `for X in C` wraps its enumerator's `Free` and never asked for
the runtime either; such a program does not compile on pin v403. Guarded now by
`test/test_forin_enumerator_free_without_try.pas`.
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 203b8a8e8.

## Breadth after the fix — five cross targets, every for-in test

`gate.sh quick` is x86-64 and that is the instrument this defect walked past, so
the fix was measured against the population it changes: every `test/*.pas`
containing a `for X in`, built for each cross target and diffed against the
x86-64 build of the same source. `PXX_ALLOW_FULL_SUITE=1` lifted for exactly
that reason.

| target | ok | diff | skipped | total | mechanism control |
| --- | --- | --- | --- | --- | --- |
| i386 | 33 | 1 | 11 | 45 | FIRES |
| riscv32 | 32 | 2 | 11 | 45 | FIRES |
| xtensa | 25 | 1 | 19 | 45 | FIRES |
| aarch64 | 34 | 0 | 11 | 45 | FIRES |
| arm32 | 33 | 1 | 11 | 45 | FIRES |

Every total is 45 — the precondition that the sweep ran the whole population,
not a subset that happened to build. The single `diff` on four rows is
`POSCTL_must_differ`, a planted row printing `SizeOf(Pointer)`, which must
report DIFF. riscv32's second is `lib_math_fast_tolerance`, **measured to differ
on pin v403 as well** — pre-existing, not this change.

**THE PLANTED CONTROL CANNOT FIRE ON aarch64 AND I NEARLY BANKED ITS `diff=0`
ANYWAY.** `SizeOf(Pointer)` is 8 on the oracle and 8 on aarch64: the expected
value equals the failure value, so that row passes whether or not the comparison
works. The `mechanism-control` column is the repair — target-independent, it
takes a pair the sweep just compared EQUAL, perturbs one byte and asserts the
comparison reports it. A control drawn from a 32-bit assumption is not a control
for a 64-bit target.

The 11 skips are named and accounted for: two `*_fail` negative tests, two that
do not build on x86-64 **identically on pin v403** (`test_auto_locals`,
`test_fgl_use`), and six stackful-generator programs, which are x86-64 only by
construction. xtensa's extra 8 are units it does not carry.
