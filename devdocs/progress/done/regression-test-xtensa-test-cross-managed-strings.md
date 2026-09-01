---
prio: 70
track: A
status: done
---

> **Track A from the job NAME `test-xtensa`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_cross_managed_strings.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-xtensa#src:test/test_cross_managed_strings.pas at 6a38839c2f81 in step 18/32, `./compiler/pascal26 --target=xtensa --platform=posix --x` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T22:24:11Z
- **Test source:** test/test_cross_managed_strings.pas tools/run_target.sh +4
- **Failing step:** line 18 of 32 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  ./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh /tmp/xt_backjump.pas /tmp/xt_backjump
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-xtensa#src:test/test_cross_managed_strings.pas'` at 6a38839c2f81286e8d6a5552c94ae5dd81de61b0

## Range
> **The named sha `6a38839c2f81` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6a38839c2f81`, last good `156be41b504a`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:2: error: target xtensa: the forward call to __pxx_run_finalizers at code offset 59154 cannot reach its body at 619376 (CALL0/CALL8 reach +-512 KiB). A BACKWARD call this far is widened automatically; a forward one cannot be, because the call site was sized before the body existed. Rebuild with --xtensa-long-calls, which reserves the long form at every forward call site (bigger and slower, and the only thing that builds an image this large today)
(tail)
ok: /tmp/testmgr-scratch-1106885/xtw_mstr  [code=278380B  data=6144B  bss=42344B  procs=276]
ok: /tmp/testmgr-scratch-1106885/xtw_mstr_x64  [code=114456B  data=6168B  bss=42548B  procs=247]
ok: /tmp/testmgr-scratch-1106885/xtc_mstr  [code=311148B  data=6144B  bss=42344B  procs=276]
pascal26:2: error: target xtensa: the forward call to __pxx_run_finalizers at code offset 59154 cannot reach its body at 619376 (CALL0/CALL8 reach +-512 KiB). A BACKWARD call this far is widened automatically; a forward one cannot be, because the call site was sized before the body existed. Rebuild with --xtensa-long-calls, which reserves the long form at every forward call site (bigger and slower, and the only thing that builds an image this large today)
  in: /tmp/testmgr-scratch-1106885/compiler/builtin/softfloat.pas
  near: , r ) ; end . >>> unit softfloat ; 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage — 2026-09-01, frankB (Track A)

**Real regression, cause identified, and it is NOT a codegen bug.** Resolved by
fixing the row and moving the standing defect to
[[feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image]], which this
falsifies part of.

### The repro line in this ticket does not work

`--job 'test-xtensa#src:test/test_cross_managed_strings.pas'` returns
`testmgr: no jobs match` (exit 1). The real name is `test-xtensa#122`, from
`--tier full --list`. Auto-filed repro lines are a starting point, not a fact.

### What actually fails

Step 18 is the `xt_backjump` row, which does not name a source of its own
because the Makefile GENERATES it (a 118 KB awk-emitted program, 3000 `if`s).
Its subject is a BACKWARD jump past J's +-128 KiB. What fails is unrelated to
that: the forward CALL to `__pxx_run_finalizers`.

```
call site         59154
body             620060
distance         560906
CALL8 reach      524288
OVER BY           36618 bytes   (7.0% past the limit)
```

`--xtensa-long-calls` builds the identical source, so the mechanism is the known
capability limit, not new codegen.

### The cause, measured rather than bisected

The watcher's range (`156be41b504a`..`6a38839c2f81`) holds exactly one buildable
change: `compiler/builtin/builtinheap.pas` +71 in `4419e1aa7`, the OOM-message
fix. That is a *builtin* -- consumed when compiling the target program, not
linked into `pascal26` -- so the arms can be swapped with no compiler rebuild
and no bisect:

```
builtinheap.pas @156be41b504a  ->  ok:  [code=622444B  procs=171]
builtinheap.pas @HEAD          ->  error: 59154 cannot reach 620060
```

**The image did not grow. 622444B both ways.** The commit REORDERED it, moving
`__pxx_run_finalizers` to the tail while its earliest caller stayed put. So a
commit that added no bytes moved the body 36618 out of reach -- which is the
finding worth keeping, and it is now on the feature ticket.

### The fix applied

`--xtensa-long-calls` on the **call0 arm only** of that row. Verified the row
still tests its subject: both `count_bytes.py` positive controls still find the
long backward-jump sequence exactly once (`a09980a00900` call0,
`908880a00800` windowed), and both ABIs still print `acc=21 iters=3` matching
the x86-64 oracle under qemu. The **windowed arm keeps no flag** -- it lays out
at 556908B and still builds -- so the incidental "a large image builds without
being told" coverage survives there instead of being lost with the line.

Not masking: shrinking the generated body to duck the wall was the alternative
and it would have destroyed the subject, which needs ~130 KB to cross J's range
at all.
- 2026-09-01 — resolved, commit 19125e02e.
