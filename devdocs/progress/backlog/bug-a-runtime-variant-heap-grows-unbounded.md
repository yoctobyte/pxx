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

## 2026-07-22 progress (fable-abcnp): three leak layers fixed, one narrowed

**Fixed (landed, gated):**
1. **Promo temp-slot re-init orphan** — IRPromoTempSlot emitted a per-visit
   PXXPromoInit that blindly re-tagged the slot INLINE while it still held last
   iteration's heap payload: one managed allocation orphaned per loop pass.
   Now: one prologue zero via SymIsHiddenArgTemp; every valid-slot writer
   (FromInt/FromStr/StoreBig) already releases the old payload itself.
2. **Wide-literal string arg leak** — IRPromoCall bypasses the AST call path's
   materialised-managed-arg owning-local machinery, so the digit text passed to
   PXXPromoFromStr leaked one refcount-1 string per evaluation. Now bound
   through a hidden owning tyAnsiString local.
3. **No scope-exit release for promo slots** — a call that spilled a promo
   value to the heap tier leaked its payload once per call. Added a
   TypeIsPromoInt arm to EmitManagedLocalCleanup (x86-64) and the aarch64
   epilogue (PXXPromoClear).

Probes now FLAT: `(x - y) & 0xFFFFFFFFFFFFFFFF` in a def called 200k times;
module-level `r = i & MASK`; `i & m`. Pascal promo locals in a loop: flat.

**REMAINING (narrowed, pure-Pascal 5-line repro):** the heap-tier BITWISE
helper path still leaks per operation when an OPERAND is heap-tagged:

```pascal
var m, d: PromoInt64; k: Integer;
begin
  m := 18446744073709551615;          { heap tier }
  for k := 1 to 200000 do d := m and 65535;   { 12.4 MB; `or` = 137 MB }
end.
```

The leak is inside PXXPromoAnd/Or's `StoreBig(dst, BBitwise(SlotBig(a),
SlotBig(b)))` chain (~60B per AND, ~690B per OR-with-heap-result). Generic
replicas of the shape (record-with-dynarray fn results, nested as const args,
string-result-through-deref-store) are all FLAT, so it is something specific
in those helpers' code — suspect list: TBitBuf locals (large fixed arrays?),
BFromBuf/BMagToBuf temps, or a retain imbalance on `FuncName := call` of
TBig inside promoint compiled under the frozen/managed split. uforth's empty
DO LOOP still grows (its boundary compare produces heap u64s every pass), so
this residual is the dominant remaining cost there.

## 2026-07-22 (later): layer 4 root-caused into its own ticket

The residual is NOT promoint-specific: any managed-record function result
raw-copied into a REUSED destination (loop within one frame) orphans the
dest's previous handles — filed as
[[bug-a-managed-record-return-into-reused-dest-leaks]] (generic 15-line
repro, 117 B/iter). This umbrella stays open pending that fix; uforth's
DO LOOP growth is dominated by it.

## PARTIAL FIX — 4 layers closed, microbench path still leaks (Track T re-measure 2026-07-22)

Track A closed four leak layers:
- `ca293f1c` — three promo-int heap-leak layers (variant-heavy loops grew unbounded)
- `528e67d3`/`86d9d3c3`/`c4f4c0b0` — layer 4: managed-record-return into a
  reused/aliased dest leaked the dest's managed fields; released before the
  epilogue copy.

Re-measured with a compiler built clean at origin HEAD (4944278f, converged
fixedpoint — NOT the daemon's mid-bisect binary, which misled a first attempt):

| workload | baseline @afbb6af5 | now @4944278f |
| --- | --- | --- |
| microbench-doloop | 582 MB | **552 MB — still linear, still leaking** |
| prelim | 32 MB | 31 MB |
| core | 166 MB | 158 MB |

So the four fixed layers did not dominate the **microbench** — a pure-integer
Forth-stack loop (DUP/LSHIFT/XOR/SWAP/AND, DROPs its result). Its RSS still
climbs monotonically to ~552 MB. There is a **remaining layer** in the
Forth-stack integer-cell path: uforth pushes numbers onto its data stack and the
popped/consumed cells are not reclaimed, ~one leaked allocation per stack op.

The earlier isolation still holds and points the remaining hunt: a pure-int
*NilPy* loop (`x = (x ^ (i<<1)) & 65535`, 30M iters) stays flat at 0 MB, so the
remaining leak is NOT the native-int tier — it is whatever boxing uforth's data
stack uses for its cells (list-of-variant, or the promo/variant slot for a value
that lives on a Python list rather than in a scoped local). That difference —
value on a long-lived container vs a scoped local — is the likely seam: the four
fixed layers were scoped-local/return-dest lifetimes; a cell parked on the data
stack has no scope end to trigger release.

Ticket stays OPEN for the remaining layer. bench.tsv now carries post-fix rows,
so the /bench page tracks any further progress.
