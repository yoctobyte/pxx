---
track: U
prio: 55
type: decide
---

# decide: how to stop the pyeval exec'd-word per-call leak (uforth doloop 553 MB)

The last layer of [[bug-a-runtime-variant-heap-grows-unbounded]]. Compiled
NilPy code is flat; every PYTHON-bodied stdlib word call leaks ~4-5 KB
because uforth's `exec_python_inline` allocates per call: an env TPyDict
({vm, push, pop, fpush, fpop}), an ns TPyDict, 5 bound-method heap pairs,
the rebuilt wrapper string — and NilPy has no object reclamation, so dict/
list/bound-method instances whose bindings die are never freed (CPython
frees them by refcount, hence its flat 24 MB).

## Options

1. **Upstream uforth change (small, honest?):** hoist env/wrapper
   construction out of the hot path — cache `{src → (env, __body__)}` on the
   VM once per word. ~15 lines in uforth.py, helps CPython too (it currently
   re-execs the def per call: ~3 ms/word there as well). Downside: the bench
   stops witnessing the missing NilPy reclamation — the language gap stays,
   hidden.
2. **NilPy object lifetime (the real fix, big):** refcount or scope-reclaim
   TPyDict/TPyList/bound-method instances when their binding dies (the
   `xs = []` reassignment path already reclaims — extend that to frame exit
   and dict internals). Track A/N arc; touches the variant slot ARC rules
   (pylib slots already refcount VT_STRING).
3. **Both:** land 1 now (bench sanity, uforth usable), keep 2 as the ranked
   language-gap ticket.

## Recommendation
Option 3. File the NilPy-reclamation work as its own Track A/N ticket sized
honestly; do the uforth hoist immediately (its repo is ours, and CPython
gains too). The umbrella ticket then closes, replaced by the language-gap
ticket.

## RESOLVED by user (2026-07-22)

uforth will NOT be changed — it is a test case; if there is an improvement
suggestion it belongs as a ticket in the uforth repo, not here ("for us it's
not relevant — and actually we should be thankful for revealing bugs").
The remaining work is NilPy object reclamation, which must be fixed either
way: Python code leaking memory is not a selling point — leaks should come
from application bugs, not compiler errors. (With the fair caveat that this
is genuinely hard — most complex applications under any compiler leak or
fragment; FPC's 2010s threaded-ansistring leaks being the cautionary tale:
threading × memory management IS hard.)

Re-filed as [[feature-nilpy-object-reclamation]] (Track A, p55).

## Log
- 2026-07-22 — resolved, commit a98b3f1f.
