---
prio: 70
track: A
status: done
---

> **Track A from the job NAME `test-xtensa`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_signal_default_revert_b336.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-xtensa#src:test/test_signal_default_revert_b336.pas at 370170edaffe in step 1/2, `./compiler/pascal26 --target=xtensa --platform=posix --x` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T17:57:52Z
- **Test source:** test/test_signal_default_revert_b336.pas tools/run_target.sh +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_signal_default_revert_b336.pas`.
  ```
  ./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh -Fulib/rtl test/test_signal_default_revert_b336.pas /tmp/test_xtensa_sigdfl
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-xtensa#src:test/test_signal_default_revert_b336.pas'` at 370170edaffea9713057a1bf65f9a616165d9685

## Range
> **The named sha `370170edaffe` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `370170edaffe`, last good `5d983997a05a`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:763: error: undefined variable (PAL_ERR_UNSUPPORTED)
pascal26:783: error: undefined variable (PAL_ERR_UNSUPPORTED)
(tail)
pascal26:763: error: undefined variable (PAL_ERR_UNSUPPORTED)
  in: /tmp/testmgr-scratch-1216987/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near: Int64 ; begin Result := PAL_ERR_UNSUPPORTED >>> ; end ; 
pascal26:783: error: undefined variable (PAL_ERR_UNSUPPORTED)
  in: /tmp/testmgr-scratch-1216987/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near: Integer ; begin Result := PAL_ERR_UNSUPPORTED >>> ; end ; 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## VERIFIED FIXED 2026-09-01 (frankC) — no longer reproduces at HEAD

Swept as part of "which of the 12 open auto-filed regressions still
reproduce?". Re-ran this ticket's OWN job recipe at `2d9878ac8`, compiler
`6afb21f66d10` (built from the pin, self-host fixedpoint converged):

```
PXX_ALLOW_FULL_SUITE=1 tools/testmgr.py --tier full --job 'test-xtensa#src:test/test_signal_default_revert_b336.pas'
```

**GREEN, twice.** Run a second time deliberately: a single green run on a
regression that may be intermittent proves nothing, and this test's population
includes at least one known race. Two independent runs, both green.

**Cause identified, not merely dated:** `db706c2da` — the posix backend never
declared `PAL_ERR_UNSUPPORTED`, which `f9e495823`'s two new `{$ifdef
CPU_XTENSA}` refuse-arms then referenced. That commit ADDS the constant to
`lib/rtl/platform/posix/platform_backend.pas:302`, and it is an ancestor of
HEAD, so the chain is causal rather than temporal. Both job steps pass: compile
is clean and `run_target.sh xtensa` gives rc=143 as the recipe asserts.
Independently confirmed by frankA, who reached the same conclusion from
`git log -S` before we discovered we were sweeping the same folder.
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit bee5a0d19.
