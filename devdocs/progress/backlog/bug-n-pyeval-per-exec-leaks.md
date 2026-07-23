---
track: N
prio: 45
type: bug
---

# pyeval leaks per exec() call — forensics from the object-reclamation night

With object reclamation slices 1-4 landed (compiler-side churn fully
reclaims: plain dict/list/bound-method probes flat at 264 KB over 200k
iterations), the remaining uforth doloop RSS (413 MB at 20k DO-LOOP
iterations, ~6 PYTHON-word execs each) is pyeval-internal, per
EvalPyStmts call, and SCALES WITH BODY TOKEN COUNT even when the body is
never executed and the tokenization cache hits.

## Measured (size-class alloc/free counters in PXXAlloc/PXXFree, 20k execs)

`exec("x = 1\n", env)` from a method, env = {vm, push, pop} rebuilt per
call (cache hit, no def, no closure):
- one 64-byte block per exec NEVER freed (alloc 20000, free 0)
- one net 24-byte block per exec (~1M churn, 20k net)

`def __body__(): <4 lines>` + no call (leak6d probe):
- 2x 40-byte blocks per exec never freed (alloc 40009, free 9)
- 1x 64-byte per exec never freed
- 1x net 128-byte per exec (5 alloc / 4 free — dict grow block?)
- 6x net 24-byte per exec

Probes live in the session scratchpad pattern (leak4/leak6*/leak7.npy);
easily reconstructed: VM class with push/pop, loop calling a method that
builds env{vm,push,pop} and exec()s.

## Facts established

- Tokenize cache HITS (1 miss per program) — the leak is not
  tokenization; closures now ref-share token arrays (fixed).
- Same shapes WITHOUT exec() are flat — compiler-side ARC is clean.
- leak4 (exec from MODULE level) was flat pre-slice-4-followups; the
  method-context + exec combination leaks — suspect a pyeval global
  (EnvG?) or Lcl* interplay pinning, plus something allocating one
  40/64B object per EvalPyStmts that no release path sees.
- Closures registry (Closures/ClosureN) still grows one entry per
  ns["__body__"] lookup — needs recycling or dedup by (fnIdx, tokens).

## Suggested attack

Re-add the size-class counters (5-minute patch, see git history of the
night for the exact diff), then log allocation BACKTRACE-lite (a global
"current pyeval site" tag set/cleared around EvalPyStmts subroutines) to
attribute the 40/64B blocks. The 24B blocks smell like 1-2 char
PXXStrFromLit name strings (LclNames?) with one lost ref per exec.

## Valgrind attribution (2026-07-23, -dPXX_LIBC_HEAP + tools/vgsym.py)

The new libc-heap profile makes this precise. 200-iteration doloop,
aggregated definitely-lost by call-site signature (bytes, records, stack):

    1938296 B   2  PXXStrFromLit <- (blob) <- PyHostCall
    1205104 B   1  PXXObjAlloc <- ParseCall <- ParsePrimary     (pyeval expr eval)
    1048584 B   1  TPyBytes.Create <- bytearray <- VM.create    (startup, one-off)
     419360 B   2  PXXObjAlloc <- VM._make_file_source <- VM.advance_file_source
     377472 B  15  PXXObjAlloc <- pyint_to_bytes <- VM._set_active_source
     328352 B   5  PXXStrFromLit <- (blob) <- VM.tokenize
     264448 B   9  PXXStrFromLit <- (blob) <- ExecSuite
     224112 B   3  PXXObjAlloc <- list <- VM.run_forth_word
     210096 B   1  PXXStrConcat <- (blob) <- build_base_vm.w_include
     176440 B   9  PXXStrConcat <- (blob) <- Tokenize            (pyeval tokenizer)
     131008 B   1  PXXStrFromLit <- (blob) <- ParsePrimary

Reproduce:
    pascal26 -dPXX_LIBC_HEAP --proc-map uforth.py /tmp/ufv
    ... | valgrind --leak-check=full --num-callers=10 /tmp/ufv 2>&1 \
        | tools/vgsym.py /tmp/ufv.map

memcheck reports 0 ERRORS — the ARC layers are sound; these are pure
leaks. Top target: the PyHostCall string materializations (~1.6 KB/exec)
and pyeval's ParseCall/ParsePrimary object results.
