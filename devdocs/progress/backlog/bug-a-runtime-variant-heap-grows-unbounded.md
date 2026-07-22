---
prio: 55
---

# issue: runtime heap grows unbounded in a dynamic/variant-heavy loop (long-running programs OOM)

- **Type:** issue — runtime memory (efficiency, but unbounded → a long enough
  run OOMs, so more than cosmetic). **Track A** (shared runtime: variant
  boxing / value lifetime / heap). Tag O (alloc-path). Filed by Track T from
  the uforth benchmark; T owns the tool, not the bug.
- **Found:** 2026-07-22, via `tools/uforth_bench.py`.

## Symptom
pxx-compiled uforth's peak RSS is wildly higher than CPython's and **grows
linearly and without bound** while it runs:

| workload | pxx peak RSS | CPython RSS |
| --- | --- | --- |
| microbench-doloop (20k-iter Forth loop) | 582 MB | 24 MB |
| core | 166 MB | 24 MB |
| prelim | 32 MB | 24 MB |

RSS sampled over the microbench (which DROPs its result — retains nothing):

```
t=1.0s 19MB  t=1.1s 33  t=1.2s 47  t=1.3s 61  t=1.4s 75  t=1.5s 89
t=1.6s 104   t=1.7s 118 t=1.8s 130 t=1.9s 144 t=2.0s 157 ...  -> 582MB
```

~14 MB per 100 ms, monotonic, no plateau, for a bounded loop that produces no
lasting data. That is allocation-per-iteration never reclaimed mid-run.

## What it is NOT (isolated 2026-07-22)
- **Not native-int codegen.** A pure-integer NilPy loop, 30M iterations of
  `x = (x ^ (i << 1)) & 65535`, stays flat at **0 MB**. Values that stay in the
  promoint native-int tier do not allocate, so this is not the arithmetic path.
- **Not "the GC never runs".** A NilPy loop that allocates a list and
  periodically reassigns `xs = []` stays flat at ~1 MB — reclamation works when
  a binding is dropped.
- **So it is the DYNAMIC / VARIANT path specifically.** uforth's data stack
  holds tagged cells and it dispatches through exec'd PYTHON-bodied words (141
  in the .UFO stdlib + `exec()` in uforth.py). The growth tracks that path, not
  the typed one.

## Hypothesis (for whoever picks it up — NOT verified)
Every Forth stack operation boxes a value as a heap variant, and the values
popped/consumed by an operation are not freed — so a tight stack-churning loop
leaks one (or more) variant cell per iteration. The exec/PYTHON-body dispatch
path is a second candidate (a temporary allocated per dynamic call and
retained). Both fit "linear in operations, zero in the typed path".

Relevant recent work to check against: promoint stage 3
([[decide-promoint-rvalue-representation]] Option A — a promo rvalue is a heap
slot address, every op a runtime helper). If a variant/promo rvalue's slot is
heap-allocated per op and its lifetime is not tied to a scope that ends, that is
exactly this shape. Confirm whether the microbench's numbers go through the
promo/variant slot path.

## Repro
```
# build a CURRENT compiler (pinned stable can't lex uforth), then:
pascal26 ~/projects/uforth/uforth.py /tmp/uf
printf ': B 0 20000 0 DO DUP 1 LSHIFT OVER XOR SWAP 1 AND XOR LOOP DROP ;\nB BYE\n' > /tmp/mb.fr
( cd ~/projects/uforth && /usr/bin/time -v /tmp/uf /tmp/mb.fr )   # watch Maximum resident set size
# or sample /proc/<pid>/status VmRSS over the run — it climbs linearly.
```
`make bench-uforth` records the peak RSS per workload into bench.tsv and the
web /bench page, so the number is tracked going forward.

## Why it matters
Correctness is fine — programs produce right answers. But unbounded growth
means a long-running dynamic NilPy program (a server, a REPL, a big batch)
OOMs, and even short runs pay a 5-24x memory tax. This is the one real
follow-up from the uforth benchmark; the SPEED numbers (0.16-0.43x vs CPython
on a dispatch-heavy VM) are good and are NOT a concern —
[[feature-t-uforth-benchmark-harness]].

## Scope / handoff
Track A (variant boxing / value lifetime / heap allocator). Start by confirming
whether the leaked allocation is the variant cell, the promo slot, or the
exec-body temporary — the isolation above says it is one of the dynamic-path
allocations, not the typed path. Not fixed under T.
