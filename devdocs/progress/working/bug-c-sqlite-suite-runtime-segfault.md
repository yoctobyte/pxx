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

## RESOLVED 2026-07-08 (fable-abc, Track A/C) — IR_LEA float→int truncation misfire

Bisected (via building each commit's compiler source with the current
backward-compatible binary, since FPC can no longer seed HEAD directly): first
bad commit **4fec149a** ("C float variadic promotion + double->int conversion"),
which added `cvttsd2si` float→int truncation in C mode at three codegen sites
(IR_STORE_SYM, IR_STORE_MEM, both IR_CALL arg-push loops).

Root cause: taking the address of a single/float-typed lvalue yields an IR_LEA
node tagged with its ELEMENT type (tySingle), not tyPointer. When that address
was stored into a pointer variable, the STORE_SYM truncation
(`TypeIsFloat(IRTk[value])`, dest not float) fired on the POINTER value —
`movq xmm0,rax; cvttsd2si rax,xmm0` truncated the address to a small int,
corrupting the pointer. sqlite3AtoF then crashed on the first `*z` byte-load.
Reduced to `sqlite3AtoF("100.5")` → SIGSEGV; instrumentation showed
dest=tyPointer, value=IR_LEA tagged tySingle.

Fix (compiler/ir_codegen.inc): exclude IR_LEA values from the C float→int
truncation at all four sites (`and (IRKind[<value>] <> IR_LEA)`). An address
node is never a float number regardless of its element-type tag. The genuine
00174/00175 float conversions are untouched.

Gates (all green): reduced sqlite3AtoF repro rc=0; FULL test/csqlite_suite.c
BYTE-IDENTICAL vs same-version gcc oracle (61 lines); regression
test/cfloat_lea_ptr_b195.c in test-core; cfloat_conv_b176 + c-testsuite
00174/00175 still pass; test-c-conformance 204/0/16; make test; self-host
byte-identical; test-lua green.

Filed separately (independent pre-existing bug found while writing the
regression test): [[bug-c-double-ptr-deref-narrow-to-single]] —
`(float)*doubleptr` narrows to 0 when a single is live.
