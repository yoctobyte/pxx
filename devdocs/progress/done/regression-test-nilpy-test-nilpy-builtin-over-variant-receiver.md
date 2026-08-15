---
prio: 70
status: done
owner: agent-an-night
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_builtin_over_variant_receiver.npy red at 4c9da77f9368 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T08:39:52Z
- **Test source:** test/test_nilpy_builtin_over_variant_receiver.npy test/test_nilpy_builtin_over_variant_receiver.expected +2

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_builtin_over_variant_receiver.npy'` at 4c9da77f9368ee00abe9614ae864cee612275db6

## Range
bad `unknown`, range **unknown** (first run covering this job at this tier, so there is no earlier passing sha to bound it) — **no idle bisect will happen**; this one needs hand-triage.

## Log tail
```
ok: /tmp/testmgr-scratch-2453462/test_nilpy_bvrecv26  [code=2265031B  data=45140B  bss=9260B  procs=1638]
ok: /tmp/testmgr-scratch-2453462/test_nilpy_pkgimp26  [code=2261310B  data=45972B  bss=8756B  procs=1646]
diff: test/test_nilpy_package_imports.expected: No such file or directory

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause (2026-08-15) — harness, not the compiler

The named test was never broken. `test-nilpy#649` is a TWELVE-line job that
covers two tests, because `COMPILE_RE` anchors the compiler at line start and
the second test's compile hides behind a `cd`:

```
cd test/nilpy_units/pkgcorpus && $(CURDIR)/$(COMPILER) .../test_nilpy_package_imports.npy ...
$(TESTTMP)/test_nilpy_pkgimp26 | diff -u test/test_nilpy_package_imports.expected -
```

`Job.script()` wrapped each recipe line in a BRACE group and ran them all in
ONE shell, so that `cd` reached the next line and the repo-relative
`diff -u test/test_nilpy_package_imports.expected` resolved inside
`pkgcorpus` → *No such file or directory*. Make gives every recipe line its
own shell and never leaks cwd, so the harness was simply not emulating make.

Fix (Track T, `tools/testmgr.py`): subshell per line, `(...)` instead of
`{...}`. `COMPILE_RE` deliberately untouched — widening it would resplit and
RENUMBER jobs, which reads as mass migration in tstate
(bug-t-optdiff-positional-sharding-migrates-job-identity).

Audited every other `cd` in the Makefile's recipes: line 2656 is the only one
at line start; all others are already `( cd ... )` subshells, so nothing else
was relying on the leak.

Verified: `testmgr --tier full --job
'test-nilpy#src:test/test_nilpy_builtin_over_variant_receiver.npy'` GREEN
(was red on the pkgimp diff). gate.sh quick GREEN.
- 2026-08-15 — resolved, commit 5c457c6a9.
