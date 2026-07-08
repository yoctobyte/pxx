---
prio: 60  # auto
---

# C sqlite feature suite (test/csqlite_suite.c) SIGSEGVs at runtime on master HEAD

- **Type:** bug (regression). Track A/C.
- **Found:** 2026-07-08 (fable-abc), incidentally while gating the
  bug-c-comment-terminator-greedy fix.

## Symptom
    S=library_candidates/sqlite
    ./compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src -I$S \
      test/csqlite_suite.c /tmp/csqlite_suite      # compiles OK (rc=0)
    /tmp/csqlite_suite                             # SIGSEGV (rc=139), no output
Expected (per done/bug-c-create-trigger-huge-alloc-oom.md, v185): the full
battery is byte-identical to a same-version gcc oracle:
    gcc -no-pie -D_GNU_SOURCE -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION=1 \
      -I$S test/csqlite_suite.c /tmp/sqver.c -o /tmp/oracle -lm
    # /tmp/sqver.c: const char sqlite3_version[]="3.46.0";
The gcc oracle runs clean (61 lines). pxx binary crashes before any output.

## NOT caused by the stray-token change
Verified: rebuilt the compiler from the PRE-change source (git stash) — it
produces a byte-identical csqlite_suite binary (code=4024556B) that segfaults
identically. So this is a pre-existing master regression, independent of
bug-c-comment-terminator-greedy. Bisect between the v185 green state and HEAD.

## Next
- Confirm on origin/master (rule out local tree drift) and check tstate/ for
  whether the watcher already caught it.
- Bisect the compiler commits since the v185 sqlite-green checkpoint; the crash
  is at runtime with zero output, so likely early (entry/global-init/setjmp or a
  codegen change to a hot sqlite path), not deep in the SQL script.
- Reduce to a minimal C repro, then fix in the owning lane.

## Gate
test/csqlite_suite.c runs and is byte-identical to the same-version gcc oracle
again; make test + self-host byte-identical.
