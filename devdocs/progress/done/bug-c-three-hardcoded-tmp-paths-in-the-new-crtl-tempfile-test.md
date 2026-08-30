---
track: C
prio: 45
type: bug
blocked-by: []
found-by: frankT
created: 2026-08-30
summary: "test/c_crtl_tempfile_and_unlocked.c (f157966e0) writes /tmp/noXs, /tmp/pxxprobeXXXXXX and /tmp/pxxprobedXXXXXX at RUNTIME, so no Makefile sweep reaches them and testmgr cannot privatize them — two concurrent runs share the file. Caught by tools/testmgr_hardcoded_tmp_devtest.py, which is red on master because of it. The guard's own message carries the exact fix."
status: done
---

# Three hardcoded /tmp paths in the new crtl tempfile test

Filed by **Track T**, which owns the guard and not the file.
`tools/testmgr_hardcoded_tmp_devtest.py` went red the moment `f157966e0`
landed, and it is the only red in the tools guard set that belongs to another
lane.

```
test/c_crtl_tempfile_and_unlocked.c    /tmp/noXs
test/c_crtl_tempfile_and_unlocked.c    /tmp/pxxprobeXXXXXX
test/c_crtl_tempfile_and_unlocked.c    /tmp/pxxprobedXXXXXX
```

**Why a sweep cannot fix it and the guard exists.** These are written at
RUNTIME by the compiled program, not by a recipe, so no Makefile rewrite
reaches them and testmgr's per-run privatisation cannot either. Two concurrent
runs — which is the normal state on a box running a watcher beside a dev
session — share the same file, and the failure that produces is a *wrong
result*, not a crash.

## The fix, in the guard's own words

Read the directory from the environment, in this order:

```c
const char *dir = getenv("TESTMGR_TMP");
if (!dir) dir = getenv("TESTTMP");
if (!dir) dir = "/tmp";
```

**`TESTMGR_TMP` first and this order is not cosmetic:** testmgr launches jobs
through an environment allowlist (`ENV_ALLOW_PREFIXES` = `PXX_ TESTMGR_ LC_
QEMU_`), so `$TESTTMP` alone **does not reach the job** and its fallback is the
shared path the guard rejected the literal for. `TESTMGR_TMP` is set per run to
a pid-keyed directory testmgr creates. `TESTTMP` second, because that is what
`make test TESTTMP=$(mktemp -d)` exports. The `/tmp` default keeps a bare run
byte-identical.

`XXXXXX` suffixes suggest `mkstemp`, which does not remove the problem: the
template's DIRECTORY is still shared, and `/tmp/noXs` has no template at all.

## Not fixed here

T owns the tool, never the bug. The file is Track C's and the change is three
lines, but a C test's runtime behaviour is the owning lane's to verify — and
the guard is red on master until it lands, so this is not a background item.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
