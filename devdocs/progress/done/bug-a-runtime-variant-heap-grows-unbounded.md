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

## DIAGNOSED — the remaining layer is variant-box lifetime on reassignment (Track T, 2026-07-22)

Not fixing (Track A's), just localizing, per the user. valgrind/heaptrack are
useless here — the x86-64 build uses a custom mmap arena allocator
(builtinheap.pas `{$else}` path: FreeList/FreeBins/HeapPtr bump); the libc
calloc/free path is `{$ifdef PXX_ESP_IDF}` only. perf uprobes are blocked
(`perf_event_paranoid=4`, no root) and gdb break-per-call is far too slow
(startup alone allocates thousands of times loading the 141 .UFO PYTHON words).

So instead: **reduce uforth to a minimal NilPy repro.** Peak RSS, 2M-iter loops,
compiler at origin HEAD (4944278f). Ladder:

| repro | peak RSS | leaks? |
| --- | --- | --- |
| plain-int local, `x = (x^(i<<1))&65535` (30M iters) | 0 MB | no |
| plain-int list append/pop | 0 MB | no |
| plain-int function-call result | 0 MB | no |
| **variant local reassigned, `v = pick(i)`** | **47 MB** | **YES** |
| variant-int list append/pop | 57 MB | yes |
| string list append/pop | 29 MB | yes |

where `pick(i)` returns `"neg"` for i<0 else `i & 255` — so its result is a
VARIANT, but at runtime always the int arm. The minimal repro is ~10 lines and
needs NO container, NO string payload, NO pop:

```python
def pick(i):
    if i < 0:
        return "neg"        # makes pick's return type VARIANT
    return i & 255          # ...but every actual value is a plain int
def main():
    v = 0
    i = 0
    while i < 2000000:
        v = pick(i)         # reassigning the variant local leaks the OLD box
        i = i + 1
    print(i)
main()
```

### The finding
A variant value's heap box is **not released when its binding is overwritten**.
It is payload-agnostic — the box leaks even when the payload is a plain int with
no managed content — so it is the variant **slot/box** itself, not a managed
string/record inside it (those were the earlier, already-fixed layers). No
container and no scope-exit is needed; a plain reassignment `v = <variant>` in a
loop orphans the previous box every iteration.

This is exactly the seam [[decide-promoint-rvalue-representation]] Option A
creates: a promo/variant rvalue is a heap-slot address, and on reassignment the
old slot must be freed before the new one is stored. The fix belongs at that
store/overwrite point (and the matching scope-exit / container-overwrite paths).
Track A. Repro compiles with any current compiler; `make bench-uforth` keeps the
uforth-scale number (552 MB) tracked as the regression/verification signal.

## 2026-07-22 narrowing #2 (fable-abcnp): remaining layer = pyeval exec'd PYTHON words

After the 4th layer (managed-record return into reused dest, resolved
2026-07-22) the COMPILED path is flat: an empty `: T 200000 0 DO LOOP ; T` and
a native-word churn loop (`I 1 + DROP I I * DROP`, DUP/DROP) hold ~20 MB at
any iteration count. The bench's microbench-doloop is still 553 MB because its
body is built from PYTHON-bodied stdlib words. Per-op RSS at 20k iterations
(5-deep stack, one op per iteration):

- native compiled words (DUP DROP): 20 MB — FLAT
- `1 LSHIFT` 105 MB · `XOR` 99 MB · `1 AND` 99 MB · `OVER` 133 MB ·
  `SWAP` 115 MB — all PYTHON-bodied (CORE.UFO), ~4-5 KB leaked per call.

So the surviving leak is uforth's `exec_python_inline` path: per call it
builds an env dict {vm, push, pop, fpush, fpop} (TPyDict + bound-method
boxes), dedents + re-wraps the source into a `def __body__():` string, execs
(pyeval parse), and calls the closure — and those per-call structures are
never reclaimed under pxx (NilPy object/dict instances have no GC; CPython
frees them by refcount). Candidate fixes: (a) pyeval-side caching keyed on
the source string (parse once per word, reuse env), (b) uforth-side: hoist
env/wrapper construction out of the hot path (upstream change), (c) NilPy
runtime: reclaim dict/list/bound-method instances whose binding dies at
frame exit. (a) is the local, biggest-win option: the 141 stdlib words are
static strings. Track N/A shared — pyeval.pas is builtin.

Bench after layer 4 (uforth_bench --runs 1): doloop 553 MB (was 582),
core 158 MB (was 166), prelim 32 MB — the deltas match the compiled-path
fixes; the bulk is this exec layer.

## Layer 5 FIXED (fable-abcnp, 2026-07-22): variant boxing double-retained call-result strings

The Track T reduction above (`v = pick(i)`) root-caused: pick's Result is
inferred ANSISTRING (from the `return "neg"` arm — NOT a payload-agnostic
int box), and `v = pick(...)` boxes the call-result handle into the variant
slot via IR_VAR_STORE, which retained UNCONDITIONALLY. A call result is
already owned (+1, ownership transfers), so every boxed call-result string
leaked one handle — the `return i` case leaked identically (variant→string
conversion helper allocates the text). Fix: IR_VAR_STORE now skips the
retain for CALL results and concat BINOPs, the same discrimination
IR_STORE_SYM has always applied; x86-64 + i386 + arm32 + aarch64
(riscv32/xtensa have no variant store). Reduction repro: 62.7 MB → 288 KB.

Bench unchanged (doloop still ~553 MB): the reduction found a REAL adjacent
leak, but the exec'd-PYTHON-word path leaks via per-call TPyDict/bound-method
instances — that is [[feature-nilpy-object-reclamation]] (user resolved
[[decide-uforth-exec-leak-strategy]]: no uforth changes; fix the compiler).
This umbrella stays open, gated on the reclamation ticket; bench.tsv keeps
the regression signal. Also filed en route:
[[bug-nilpy-mixed-str-int-return-segfault]] (pre-existing crash).

## PARTIAL FIX #2 verified — local reassignment reclaims; container path remains (Track T, 2026-07-22, @c5cdc449)

Re-ran the minimal ladder on a fresh fixedpoint compiler at HEAD:

| repro | baseline | now | |
| --- | --- | --- | --- |
| I — variant LOCAL reassign (`v = pick(i)`) | 47 MB | **0 MB** | FIXED |
| H — variant-int list push/pop | 57 MB | 58 MB | leaks |
| G — string list push/pop | 29 MB | ~33 MB | leaks (no regression — a 59 MB reading was a noise spike; 35/35/31 on reruns) |
| D — variant list push/pop | 19 MB | 24 MB | leaks |
| A — plain-int list (control) | 0 MB | 0 MB | ok |
| uforth microbench | 552 MB | 552 MB | unchanged |
| uforth prelim | 31 MB | 31 MB | unchanged |

**Clean split:** the variant **local-reassignment** box is now reclaimed on
overwrite (I: 47→0). What remains is **container/collection** reclamation — a
variant or string element parked in a list is not freed when it is popped or
overwritten (H, D, G). uforth is unchanged because its Forth data stack IS a
list of variants, so it rides entirely on the container path, not the
local-reassign path that got fixed.

Remaining work = free the element's box on list pop / element-store-overwrite /
container teardown (the [[feature-nilpy-object-reclamation]] lane). uforth's
552 MB microbench is the scoreboard; it drops when the container path reclaims.

## MOSTLY FIXED — container reclamation landed; ~28x cut (Track T, 2026-07-23, @684715e0)

The managed-string arg-temp + pyeval + char-to-string + per-call TPyList fixes
(2edd88fa, 4740c916, 5d3693bb, 98aaecd0, a0574d81, …) closed the container path.

**Every isolated repro is now clean:**

| repro | baseline | now |
| --- | --- | --- |
| I variant local reassign | 47 MB | **0 MB** |
| H variant-int list push/pop | 57 MB | **0 MB** |
| G string list push/pop | 29 MB | **0 MB** |
| D variant list push/pop | 19 MB | **0 MB** |
| J exec() in a loop | (new) | **0 MB** |
| A plain-int control | 0 MB | 0 MB |

**uforth (the scoreboard):**

| workload | baseline | now |
| --- | --- | --- |
| microbench (20k) | 552 MB | **35 MB** (16x) |
| prelim | 31 MB | 15 MB |
| core | 158 MB | 103 MB |

### Residual — small, still linear, NOT reproduced by any simple repro
uforth microbench peak vs iters: 10k→24 MB, 20k→34 MB, 40k→55 MB — still linear
at **~1 KB/iter** (was ~28 KB/iter: a ~28x cut). So a small leak remains, but it
is NOT any of the isolated patterns above (all 0 MB now, including exec() in a
loop). It is some uforth-specific COMBINATION — most likely an exec'd
PYTHON-body word that manipulates the variant data stack, a path the simple
repros don't hit. Chasing it with more blind repros is diminishing returns;
Track A would want to profile uforth directly (or instrument PXXAlloc caller
addresses in a throwaway build) for the last layer. The 16x/28x win is the
headline; the scoreboard (`make bench-uforth`) tracks any further drop.

## Residual CLOSED on microbench+prelim (Track A, 2026-07-23, @32fdbcda)

The ~1 KB/iter microbench residual was the isNilPy managed-string
**deref-to-const arg leak** ([[project_nilpy_managed_deref_const_arg_leak_fixed]],
root-fixed 32fdbcda): PyFindMethCI's `meths[i].NamePtr^` to a `const AnsiString`
param leaked one handle per method scanned per host-dispatch — the doloop's
dominant per-exec allocation. Root-fixed in the arg lowering (isNilPy owns a
managed-string deref arg via a hidden local at all 6 arg-temp sites); the 3
hand binds are removed.

`uforth_bench --runs 1` after the fix:

| workload | baseline | last-noted | now |
| --- | --- | --- | --- |
| microbench-doloop | 552 MB | 35 MB | **13.8 MB** (below CPython's 23) |
| prelim | 31 MB | 15 MB | **15.1 MB** |
| core | 158 MB | 103 MB | **100.3 MB** |

microbench RSS is now FLAT across 10k/40k/80k iters (~14 MB, no per-iter
growth) — the unbounded-growth symptom is GONE on the scoreboard workload,
and microbench+prelim sit at/below CPython.

**Remaining: `core` at 100 MB (~4x CPython).** Not yet characterised as leak
vs static working set — core is a fixed (non-iter-parameterised) workload, so
the RSS-slope test doesn't apply directly. Ticket stays OPEN for that: confirm
whether core's 100 MB grows with a longer/looped core run (leak) or is a flat
high-watermark (just memory-heavy dynamic dispatch). If flat, this umbrella is
effectively done — the "unbounded growth → OOM" concern is resolved.

## core residual CHARACTERISED (Track A, 2026-07-23): it is a LEAK, O(n²), in the `:` / `S"` paths

Per the user's request, characterised whether core's 100 MB is a leak or a
static high-watermark. **It is a leak, and super-linear (≈O(n²)) in the
word-definition path.** Method: run the core suite 1×/2×/3× (tester.fr +
core.fr repeated), and isolate the constructs.

Core suite repeated (peak RSS, default mmap arena):

| workload | peak RSS |
| --- | --- |
| core ×1 | 100 MB |
| core ×2 | 385 MB |
| core ×3 | 847 MB |

Isolated constructs (2000 ops each, arithmetic control):

| workload | peak RSS |
| --- | --- |
| 2000 colon defs `: wN 1 2 + drop ;` | 200 MB |
| 2000 `S" ..." 2DROP` string literals | 324 MB |
| 2000-iter arithmetic `1 2 + DROP` (control) | **14 MB flat** |

Colon-def scaling (the smoking gun — quadratic, not linear):

| N defs | peak RSS |
| --- | --- |
| 1000 | 42 MB |
| 2000 | 200 MB |
| 4000 | 838 MB |

Doubling N ~quadruples RSS → **O(n²) memory in dictionary building.** The
arithmetic/data-stack path is FLAT (14 MB) — the earlier fixes hold. The
residual is exclusively the **compile/dictionary path**: each `:` definition
(and each `S"` literal) costs memory that grows with the number of prior
definitions. Classic shape of a growing container (uforth's word dictionary —
a list/dict held in a long-lived global variant) being copied or re-boxed on
every append with the old copy not reclaimed, i.e. append is O(n) copy and the
prior container leaks → O(n²) total.

**Handoff:** this is the [[feature-nilpy-object-reclamation]] lane, specifically
the **container-overwrite / long-lived-global-variant** reclamation path (not
the local-reassign or scope-exit paths already fixed). Likely uforth's
dictionary global reassigned per definition; confirm whether the overwrite of a
container-holding GLOBAL variant reclaims the old container (the fixed
reclamation covered locals/scoped containers; a global reassigned in a loop is
the untested seam). The microbench scoreboard is now flat/below CPython; this
`:`/`S"` O(n²) path is the last open layer.

## core O(N²) fully ROOT-CAUSED (Track A, 2026-07-23) — three distinct causes, NOT one leak

Dug into the core residual (uforth defs `: wN 1 2 + drop ;`, N=1000/2000/4000).
CPython uforth runs the SAME source flat/linear (RSS 24→26 MB, time
0.26→0.40s), so every O(N²) below is pxx-introduced, not uforth's algorithm.

**Decisive split — memory O(N²) is the ALLOCATOR, not a leak:**

| build | defs RSS 1k/2k/4k | time |
| --- | --- | --- |
| mmap arena (default) | 42 / 200 / 838 MB — **O(N²)** | O(N²) |
| libc heap (-dPXX_LIBC_HEAP) | 7 / 9 / 13 MB — **LINEAR** | O(N²) |

Same program, linear RSS under libc → the O(N²) RSS is the **mmap arena not
reusing freed large blocks**, not leaked-and-lost memory. Three root causes,
each its own fix:

1. **NilPy dict insert/lookup is O(N)** (linear, not hashed) → O(N²) compile
   TIME, and each growing dict realloc frees a >512 B buffer.
   → [[bug-nilpy-dict-insert-lookup-linear-not-hashed]] (the biggest lever:
   fixes the time AND most of the churn).
2. **Arena large-block (>512 B) reuse gap.** builtinheap exact-size bins stop at
   HEAP_BIN_MAX=512 B; larger frees go to a FreeList that does not reuse a freed
   N-byte buffer for a later (N+k)-byte request, so dict-realloc churn bumps
   HeapPtr forever → O(N²) high-water. libc coalesces → linear. This is the
   "add capacity, don't release old" at the allocator level. Track O
   (heap allocator; [[project_heap_size_class_allocator]]). Improving large-block
   reuse/coalescing would make even pathological churn linear-RSS.
3. **`bytes(seq[a:b])` leaks the intermediate** — a genuine (definitely-lost)
   leak in `VM._snapshot_input_state` (3×/line), linear here but unbounded in a
   bytes-slice loop → [[bug-nilpy-bytes-of-slice-leaks-intermediate]].

**Status of the umbrella:** the ORIGINAL unbounded-growth symptom (microbench
552 MB) is fixed and flat/below CPython. The remaining core O(N²) is now fully
attributed to the three tickets above (dict-O(N) + arena-reuse + bytes-slice),
none of which is the variant-box/container-lifetime class this umbrella was
opened for. This umbrella can close once those are filed/tracked; the real work
moves to #1 (dict) and #2 (arena), with #3 the clean leak.

## core residual CLOSED — real root was O(filesize²) file slurp (2026-07-23, @a50491d6)

The core O(N²) was NEITHER the dict scan NOR the arena-reuse gap (both earlier
theories here were wrong — chased via isolated dict-build timing and libc-vs-arena
RSS, both misleading). callgrind pinned it: 83% of instructions in PXXStrConcat,
and an n=150-vs-n=300 diff showed that cost was ~constant in def-count → it was
FILE READING, not the defs. `pyfile_slurp` appended each byte with
`Result := Result + buf[i]` (O(filesize²)); it reads the stdlib on every start
AND the program's own input, so a bigger input file cost quadratically — that is
the "O(N²) in definition count" (more defs = bigger .fr file). Fixed with
amortised-doubling capacity (+ pystr_upper/lower preallocation).

Result — uforth, mmap arena, every workload now FLAT and BELOW CPython (~24 MB):

| workload | original | now |
| --- | --- | --- |
| microbench | 552 MB | 13.3 MB |
| core | 158 MB | 13.3 MB |
| prelim | 32 MB | 13.3 MB |

defs `: wN 1 2 + drop ;`: 1k 1.64 s/42 MB → 0.37 s/6 MB; 4k 16.9 s/838 MB →
0.71 s/12 MB; 16k linear at 2.05 s/31 MB. Both time and memory O(N²)→linear.

### Umbrella RESOLVED
The unbounded-growth symptom is gone across every workload. The layers found and
fixed over this campaign: promo-int heap leaks (ca293f1c), managed-record return
into reused dest (528e67d3…), container reclamation (684715e0), managed-string
deref-to-const arg ([[project_nilpy_managed_deref_const_arg_leak_fixed]]),
bytes/owned-obj-arg-0 reclamation, and finally this O(filesize²) slurp. Spin-offs
kept as their own tickets: [[bug-nilpy-dict-insert-lookup-linear-not-hashed]]
(landed — TPyDict now O(1) hashed, a real win though NOT this umbrella's cause),
[[perf-nilpy-remaining-perbyte-string-builders]] (join/repr/fmt/strip),
and the arena large-block reuse note (Track O, latent — no longer a live problem
now that the churn is gone). Marking resolved.

## Log
- 2026-07-23 — resolved, commit a50491d6.
