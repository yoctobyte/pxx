---
track: B
prio: 50
type: bug
summary: "test/cstring_batch.c calls memrchr without _GNU_SOURCE, so its gcc ORACLE fails to compile on gcc >= 14 (implicit-function-declaration is an error there). The recipe discards gcc's stderr AND its exit status, then diffs against a missing or stale binary and reports 'cstring_batch differs from gcc' — so a broken oracle is indistinguishable from a real pxx defect. Blocks enrolling lib-test in the watcher."
---

# `cstring_batch`'s gcc oracle does not build, and the recipe reports it as a pxx diff

- **Type:** bug (test + its recipe) — **Track B** (`test/cstring_batch.c`; the
  recipe lives in the Makefile, so the `rc` half may need Track A).
  Found by Track T on 2026-08-14 while enrolling `lib-test` in the watcher
  ([[task-t-enroll-libtest-demos-watcher]]) — **this is the one thing blocking
  that enrolment.**

## What happens

```
$ gcc -w -o /tmp/csb_gcc test/cstring_batch.c ; echo $?
test/cstring_batch.c:44:15: error: implicit declaration of function 'memrchr';
                            did you mean 'memchr'? [-Wimplicit-function-declaration]
1
```

`memrchr` is a GNU extension and needs `_GNU_SOURCE`. Implicit function
declarations became an **error** in GCC 14; this box runs 15.2.0, so the oracle
has simply stopped building. Confirmed the fix is one flag:

```
$ gcc -w -D_GNU_SOURCE -o /tmp/csb_gcc test/cstring_batch.c   # 0 errors, binary produced
```

## Why it reads as a pxx bug, which is the worse half

```make
gcc -w -o /tmp/cstring_batch_gcc test/cstring_batch.c 2>/dev/null; \
/tmp/cstring_batch_gcc > /tmp/cstring_batch_gcc.txt; \
...
diff /tmp/cstring_batch_gcc.txt /tmp/cstring_batch_pxx.txt || \
  { echo 'FAIL: cstring_batch differs from gcc'; exit 1; }
```

gcc's stderr goes to `/dev/null` **and its exit status is never checked**. So
when the oracle fails to build, the recipe runs a missing (or stale, from an
earlier gcc) binary, diffs whatever that produced, and announces
`FAIL: cstring_batch differs from gcc`.

That message is the problem. It names pxx as the party that differs, when in
fact **no comparison happened** — a triaging agent starts by looking for a
codegen regression that does not exist. This is the same shape as
`gate.sh`'s old silent-fixedpoint bug: the check failed, and said something
else.

## Fix

1. `-D_GNU_SOURCE` on the oracle compile (or `#define _GNU_SOURCE` at the top of
   the .c, which also documents the dependency at the point of use).
2. **Check gcc's exit status** and distinguish the two outcomes:
   `SKIP: cstring_batch (gcc cannot build the oracle: <first error>)` versus
   `FAIL: cstring_batch differs from gcc`. An oracle that will not build is an
   absent prerequisite, like an unfetched corpus tree — not a verdict about pxx.
3. While there: the same swallow-stderr-ignore-rc shape is worth grepping for
   across the other gcc-oracle steps in `lib-test`; this one was found only
   because a watcher enrolment made it visible.

## Why it blocks the watcher enrolment

`lib-test` is otherwise ready to enrol: 166 jobs, correct per-source
attribution, 163 passing, 2 correctly skipping on an absent `external/synapse`.
This one job would make the **full tier permanently RED on every box with a
modern gcc**, for a reason that is not a pxx defect — which is precisely the
"a gate that is red teaches everyone to discount red" failure
[[bug-t-three-network-tests-flake-and-cost-real-debugging-time]] was about. So
the enrolment is held until this lands.

## Gate

`gcc -w -D_GNU_SOURCE -o /tmp/x test/cstring_batch.c` builds, the step passes,
and deliberately breaking the oracle (rename `memrchr`) produces a SKIP naming
the build failure rather than a diff verdict.
