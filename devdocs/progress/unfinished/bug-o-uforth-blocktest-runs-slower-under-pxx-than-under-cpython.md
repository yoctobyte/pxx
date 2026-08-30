---
summary: "uforth's blocktest word set takes 413s compiled by pxx against CPython's 196s interpreting the same source — the AOT compiler is 2.1x SLOWER than the interpreter it is differentially tested against, and it is now the pole of two test tiers"
type: umbrella
track: O
prio: 25
status: backlog

owner: frank-optimize
---

# pxx-compiled uforth is 2.1x slower than CPython on `blocktest`

- **Type:** bug (Track O — optimization; file-owned by Track A per O's rule)
- **Found:** 2026-08-11 by Track T while sharding `test-uforth`
  ([[feature-t-shard-the-uforth-ans-suite-per-word-set]]). **Filed, not fixed:
  T owns the tool, never the bug.**

## Measured

Per-phase timing of `make test-uforth`, compiler at `96b4b40ab`, 12-core
plexus. Each word set is run twice — once by the pxx-compiled `uforth`, once by
CPython running `uforth.py` — because the test is a differential. That makes it
an accidental but rather direct **compiler-vs-interpreter benchmark on the same
program**:

| word set | pxx (compiled) | CPython (interpreted) | ratio |
| --- | --- | --- | --- |
| `blocktest.fth` | **413.3s** | **196.0s** | **2.1x slower** |
| `core.fr` | 8.1s | 2.5s | 3.2x slower |
| `coreexttest.fth` | 6.0s | 1.9s | 3.2x slower |
| `coreplustest.fth` | 4.8s | 1.5s | 3.2x slower |
| `stringtest.fth` | 4.2s | 1.1s | 3.8x slower |
| `memorytest.fth` | 3.7s | 1.3s | 2.8x slower |
| 4 uforth corpora | 12.0s | 3.7s | 3.2x slower |

The box was contended (the watcher held a tier), so **absolute numbers run
high** — but both runtimes were contended equally in the same loop, so the
RATIO is the trustworthy part, and it is consistent at ~2-4x across every
single subject. The Makefile's own long-standing note records the uncontended
pair as ~240s vs ~80s: **3x**, same story.

## Why this is worth a ticket rather than a shrug

Nil-Python is a **compiled** frontend. Losing to CPython — a bytecode
interpreter — by 2-4x on every subject measured is the opposite of the expected
result, and it is uniform, so it is unlikely to be one pathological word.

It is also no longer only a quality question. After the sharding above,
`test-uforth#blocktest` is **the single longest job in both the `limited` and
`full` tiers**, so it sets Track T's wall time on its own:

```
limited: 14 shards, pole = test-uforth#blocktest (~268s uncontended)
full:    same pole
```

Every other uforth shard is ~28-36s, most of that the repeated `uforth.py`
compile. So this one ratio is what stands between T and a ~30s uforth
contribution — halving it is worth roughly two minutes off every deep run the
watcher makes, all day.

## Where the cause probably is NOT

Not the x86-64 instruction selection, most likely: the workload the Makefile
describes is "a memory-walk and hash workload", i.e. it leans on the NilPy
object model — dict/list indexing, integer boxing, refcount traffic — rather
than on arithmetic in registers. A uniform 2-4x across unrelated word sets
points the same way: a per-operation constant in the runtime, not a bad loop.

**That is a hypothesis from the shape of the numbers, not a diagnosis.** Do not
act on it — `devdocs/dev/root-cause-over-microfix.md` and the debugging
playbook both apply, and this repo's history is explicit that every wrong root
cause here was a plausible story nobody diffed against an oracle.

## Suggested first step

Profile the compiled `uforth` on `blocktest` (`-g -O2` + `perf`, or the
allocator counters) and find where the time goes before changing anything. The
oracle is free and already wired: the same program, same input, under CPython.

`tools/bench_timing_devtest.py` and the uforth speed harness in
[[feature-t-uforth-benchmark-harness]] are the existing instruments.

## Routing note

Filed under **O** because it is a codegen/runtime speed question and O is the
visible lane for those. If the cause turns out to be NilPy lowering rather than
the shared runtime or backend, this belongs to **Track N** — reroute rather
than split it. Whoever picks it up should decide that from a profile, not from
this ticket's guess.

## Gate

A profile naming the dominant cost, and — if a fix lands — the ratio measured
again the same way (same loop, same box, both runtimes contended equally), plus
`make test-uforth` still byte-identical to CPython on all 13 word sets.

## 2026-08-13 — re-measured, raised to prio 65, and worked around

Measured on plexus from the watcher's own log, full tier, wall 821.1s:

| job | wall | share |
|---|---|---|
| **test-uforth#blocktest** | **594.8s** | **72%** |
| selfhost-fixedpoint#00 | 131.8s | 16% |
| test-core#1139 | 108.2s | 13% |
| 2326 others | in parallel behind them | — |

This ticket's "it sets Track T's wall time on its own" was, if anything,
understated: with the matrix at 2331 jobs and a 12-core box, one job is
three-quarters of the sweep, and everything else fits in its shadow.

It also explains a second symptom that had been read as a tiering problem. The
`limited` tier cost 686s against `full`'s 821s — 84% of the price for 78% of
the jobs — which made the three-rung escalation ladder nearly pointless. The
mechanism was this job: **both tiers carried the same pole**, so neither could
be faster than it. The middle rung was collapsed today
(`perf(T): collapse the watcher's middle rung`), and that collapse is only
correct while this remains true.

### Worked around, on purpose, with an expiry condition

`test-uforth#blocktest` is now demoted out of the per-sha tiers into a new
disjoint `slow` tier (`testmgr.SLOW_SHARDS`), which the watcher runs as an idle
rung after the full matrix (`idle_slow`). The corpus is still swept; it is no
longer swept on every sha. Full sweeps drop 821s -> ~440s.

**This weakens the urgency argument above and should not be read as weakening
the ticket.** Two things stay true:

1. The quality finding is untouched and is the real point — a *compiled*
   frontend losing to a bytecode interpreter by 2-4x, uniformly across every
   subject measured, is the opposite of the expected result.
2. The workaround has a defined end: `SLOW_SHARDS` exists to be deleted. When
   this lands and blocktest is ordinary again, put it back in `limited`/`full`
   where the densest NilPy regression corpus belongs, and re-check whether the
   middle rung is worth restoring.

Raised 45 -> 65 by the user, on seeing the 72% number.

Nothing about the diagnosis changed: the "where the cause probably is NOT"
section above is still a hypothesis from the shape of the numbers, and the
suggested first step is still to profile before touching anything.

## 2026-08-14 (claude-A-N, Track N) — a WHOLE-SUITE number, not just blocktest

While closing [[feature-nilpy-corpus-uforth]], the full ANS Forth / Forth 2012
suite (`tests/runtests.fth`: prelimtest, the tester harness, `core.fr` and
eleven word-set files) was run under both engines from an identical tree:

| engine | wall | result |
| --- | --- | --- |
| CPython 3.12 | **54.66 s** | 252 lines, 0 errors |
| pxx-compiled uforth | **153.18 s** | 252 lines, 0 errors, stdout byte-identical |

**2.80x slower**, on a real mixed workload rather than one test. So this ticket's
finding is not a blocktest peculiarity — blocktest is where it was first noticed,
and the ratio holds across the whole conformance suite.

The correctness half is settled and should not be re-litigated while optimising:
the compiled binary produces CPython's exact output, so any change here has a
byte-exact oracle to hold itself against. Re-run with
`cd <tree>/tests && ../uforth_pxx runtests.fth < /dev/null`.

**Provenance:** compiler at f2f56c876, self-hosted fixedpoint build, not rebuilt
during the runs; same tree, same input, stdin closed for both (the suite blocks
on an interactive ACCEPT otherwise, which will look like a hang).

## 2026-08-14 — PROFILED. Two O(n²) operations in the NilPy string runtime

The ticket asked for a profile before anything was changed, and warned that its
own guess ("a per-operation constant in the runtime") was a hypothesis. The
guess was right in kind and badly understated in degree: these are not
constants, they are **quadratics**.

### Reproduced first, on the small subjects

`perf` is unusable on this box (`perf_event_paranoid`), so the profile is
callgrind — exact instruction counts, no sampling error. Subjects run with the
real driver prelude (`prelimtest`/`tester`/`utilities`/`errorreport`), outputs
byte-identical to CPython throughout:

| word set | pxx | CPython | ratio |
| --- | --- | --- | --- |
| stringtest.fth | 1.75s | 0.47s | 3.7x |
| memorytest.fth | 1.60s | 0.54s | 3.0x |
| coreexttest.fth | 2.59s | 0.69s | 3.7x |

Consistent with the ticket's table, so the small subjects are a valid proxy for
`blocktest` and cost seconds instead of minutes.

### The profile (callgrind, core.fr, 2.43e9 Ir total)

| function | Ir | share | calls | Ir/call |
| --- | --- | --- | --- | --- |
| **PXXStrConcat** | 1.52e9 | **62.5%** | 635,620 | 2,712 |
| PXXAlloc | 2.18e8 | 8.9% | 806,775 | 270 |
| **pystr_isascii** | 1.04e8 | **4.3%** | 130,052 | 798 |
| PXXFree | 4.9e7 | 2.0% | | |
| PXXMemZero | 4.8e7 | 2.0% | | |

633,626 of PXXAlloc's 806,775 calls come **from PXXStrConcat** — one fresh
block per concatenation. pystr_isascii is called from `PyStrCharLen` (74,440)
and `pystr_charat` (43,939).

(The binary has no ELF symbols callgrind can read — resolve addresses through
the `.map` the compiler emits beside the executable. `gdb`'s `info symbol` and
`readelf` both answer "no symbol"; this is the same blindness noted for
`readelf` on pxx binaries.)

### Scaling curves — the decisive measurement

Two NilPy micro-benchmarks, timed against CPython on the same box:

```
A:  s = s + "x"   in a loop            B:  c = s[i]   across the string
n        pxx        cpython             n        pxx        cpython
20000    0.836s     0.026s              20000    1.904s     0.018s
40000    3.479s     0.039s              40000    7.827s     0.023s
80000   16.049s     0.120s              80000   30.979s     0.029s
160000 102.630s     0.815s              160000 123.811s     0.050s
```

**Every doubling of n quadruples the time.** Both are O(n²) where CPython is
linear or flat. B is the sharper result: merely READING `s[i]` across a string
is quadratic, and at n=160k pxx is **2,476x** slower than CPython at the same
work.

So the uforth ratio is not the finding — it is a mild symptom, diluted because
uforth's strings are short. The finding is that two of the most ordinary
operations in the language are quadratic.

### Cause A — `s[i]` rescans the whole string, per index

`PyStrCharLen` and `pystr_charat` both begin with `pystr_isascii(s)`, which
scans every byte to decide whether character offsets equal byte offsets. That
scan is O(n) and it happens on EVERY index, so an indexing loop is O(n²).
`len(s)` is O(n) for the same reason.

### Cause B — every concatenation allocates and copies the whole accumulation

`PXXStrConcat` allocates a fresh block and copies both operands (2,712 Ir/call
average, one PXXAlloc per call). `s = s + c` in a loop therefore copies the
entire accumulated string every iteration. CPython's `str +=` is amortised O(1)
because it reallocs in place when the target's refcount is 1. Same shape as the known
SetLength-has-no-spare-capacity finding: an append that reallocates every time.

### The fix for A already exists in the tree and is DELIBERATELY not wired up

`PXX_FLAG_ASCII` ($0400) is a header bit `PXXStrFromLit` and `PXXStrConcat`
already compute and stamp — for free, in a loop that touches every byte anyway.
`pystr_isascii` could read it in O(1). The previous author left the note at
`pylib.pas:2139` saying exactly why they did not:

> *reading the meta word of a block that may never have carried a header is a
> claim that has to be MEASURED, and a false positive there is a silent wrong
> answer — so the flag is deliberately a separate change*

**That hazard is real, and it is structural rather than a matter of coverage.**
`PXXStrMeta` stamps `PXX_KIND_LEGACY` (= 0) as the kind for BOTH cases:

```pascal
if (orAll and $80) = 0 then PXXStrMeta := PXX_KIND_LEGACY or PXX_FLAG_ASCII
else PXXStrMeta := PXX_KIND_LEGACY;
```

So a zero meta word means either "stamped, and NOT ascii" or "no header here at
all". A block that never carried one (a `.rodata` literal — note
`PXX_FLAG_STATIC` is defined and unused) returns whatever bytes precede it, and
if bit $0400 happens to be set the answer is "ASCII" for a non-ASCII string:
wrong character offsets, silently.

**So the fix is not "read the flag" — it is "make the meta word self-certifying
first".** A positive validity marker (a magic in the unused high bits, checked
before any flag is trusted) turns the ambiguity into a decidable question, and
only then is the O(1) read safe. That is the design step, and it is exactly the
kind of thing this ticket's own instructions say not to guess at.

### Recommended sequencing

1. **A first, and it is the bigger win** — it fixes indexing, `len()`,
   iteration and slicing at once, and it is bounded: a validity marker plus one
   changed function body.
2. **B second** — in-place append when the target block's refcount is 1 and the
   block has spare capacity. Bigger blast radius (it changes the allocator
   contract) and it shares ground with the SetLength ticket, so they should be
   sized together.
3. Re-measure the uforth ratio the way this ticket specifies, and re-measure
   both scaling curves — a fix that does not flatten the curve has not worked,
   whatever the wall time says.

### Routing

Stays **O** (file-owned by A): both causes are in `compiler/builtin/**`
(builtinheap's block header, pylib's string helpers), not in NilPy lowering. The
ticket's own routing note is satisfied — this was decided from the profile.

### State: diagnosed, not fixed

Parked deliberately rather than microfixed. Nothing is half-applied — no
compiler change was made — so this returns to the backlog with the diagnosis
banked, per `devdocs/dev/root-cause-over-microfix.md`.

## 2026-08-14 — CAUSE A FIXED (pin v298). Cause B is what uforth actually pays.

`PXX_FLAG_ASCII_KNOWN` makes the header's ASCII bit decidable, so
`pystr_isascii` scans at most once per string instead of once per index.

| `c = s[i]` across the string | before | after |
| --- | --- | --- |
| n=20000 | 1.904s | 0.015s |
| n=40000 | 7.827s | 0.028s |
| n=80000 | 30.979s | 0.047s |
| n=160000 | **123.811s** | **0.106s** |

Linear, 1168x at n=160k. `len(s)` in a loop is linear too and marginally faster
than CPython (0.031s vs 0.033s at n=80k) where it had been quadratic.

The hazard this ticket flagged was handled rather than hoped away: a zero meta
word meant BOTH "scanned, not ASCII" and "nobody looked", so the new KNOWN bit
separates them, and `pystr_isascii` records what it finds — producers that never
stamped are self-healing, so no audit of every string-producing site was needed.
Soundness rests on one checkable claim: byte mutation goes through
`PXXStrUnique`'s COW, both of whose paths hand back a writable block, so both
forget the answer; `PXXStrSetLen` always allocates fresh and `PXXHdrInit` zeroes
the meta.

Verified against CPython — unicode indexing, slicing, iteration, mixed
derivations, both repeat forms, and a Pascal in-place `s[7] := Chr(200)` after
the question was asked. New test `test_nilpy_str_ascii_cache.npy`.

### And it does NOT fix this ticket's own subject

uforth's word sets moved 1.748s -> 1.736s. That is the honest result and it was
predictable from the profile: **62.5% of uforth's instructions are in
PXXStrConcat**, against 4.3% in `pystr_isascii`. uforth builds output strings by
appending; it does not index them.

So the remaining work IS cause B, and the ticket should not be closed on A.

### Cause B, scoped

`s = s + c` copies the whole accumulation per append. The fix is NOT a builtin
tweak, and it is worth stating why so nobody starts one: `PXXStrConcat(lenA,
srcA, srcB, lenB)` returns a fresh handle and **does not know the destination
slot**, so it cannot append in place without guessing. Deciding to mutate from
the left operand's refcount alone is a silent-wrong-value bug: `t := s + 'x'`
with a refcount-1 `s` would grow `s` itself, and `s` would appear to have
changed.

It needs the CALLER's intent — an IR-level append when the destination IS the
left operand — plus spare capacity in the block so the append is amortised O(1).
That is Track A codegen work sharing ground with the SetLength-no-spare-capacity
finding, and the two should be sized together.

## 2026-08-14 — CAUSE B FIXED, in two halves. uforth 2.80x -> 2.28x.

The scoping note above said the fix needs "the CALLER's intent — an IR-level
append when the destination IS the left operand — plus spare capacity in the
block". That is what landed.

### The runtime: `PXXStrAppend(strSlot, srcB, lenB)`

Takes the destination SLOT, which is precisely what `PXXStrConcat(lenA, srcA,
srcB, lenB)` cannot have. Sole owner with room to spare writes in place;
otherwise it allocates `need * 2` and copies. The doubling is the whole point —
an exact-fit block is full again on the next append, which is the same trap
[[project_pxx_setlength_no_spare_capacity_append_quadratic]] records.

Capacity comes from the allocator's own size word below the block, so no header
field moved and `PXX_HDR_SIZE` (and every codegen offset on six backends) is
untouched. The catch: "the word below the base" only means something for blocks
this path allocated, and a garbage-large answer passes `cap >= need` and writes
off the end. So the in-place branch also requires `PXX_FLAG_APPENDABLE`
($2000), which only the grow path stamps. **rc<=1 alone is not sufficient**, for
the same reason.

### The codegen: two stores, because there are two shapes

- `IRIsSelfStrAppend` / `EmitAnsiStrAppendToSym` — the tyAnsiString store. This
  is **Pascal's** shape.
- `IRIsSelfVarStrAppend` / `PXXVarStrAppend` — the tyVariant store. This is
  **Nil-Python's** shape, and finding that out was the necessary step: a
  loop-carried `s` in NilPy infers **tyVariant**, not tyAnsiString (`PXXDBG
  n.locals` says tk=22). The first half alone left NilPy at exactly its old
  0.834s. Fixing one arm of a two-shape construct and stopping is the failure
  [[devdocs/dev/normalise-dont-special-case]] describes; both arms are wired.

The variant helper answers 0 for anything that is not string-into-string or
char-into-string, and the general `PXXVarBinOp` path then runs unchanged — so
`+` on variants still has exactly one definition.

Order of evaluation differs between the two, and the guards differ with it. The
typed store requires `ScratchSafeSubtree` on the right operand: append reads the
destination AFTER evaluating the right where concat reads it before, so `s := s
+ f()` with an f that assigns to s would change answer. The variant store needs
no such guard — `IR_VAR_BINOP` takes two ADDRESSES of already-populated slots,
so the general path already reads the destination last.

x86-64 only. The other five backends keep the concat path, correct and slower.

### Scaling — both curves flat

```
Pascal  s := s + 'x'      n=20k..320k ladder, whole ladder:  0.016s
NilPy   s = s + "x"       n=20k..320k ladder:  0.115s  (CPython 0.054s)
NilPy   s += "x"          n=80000:             0.018s
```

Against the recorded quadratic (`n=160000: 102.630s`) that is the curve
flattening, not a constant-factor win.

### uforth: the ticket's own subject

Full ANS/Forth 2012 suite (`tests/runtests.fth`), stdin closed, both engines,
same tree, output **byte-identical** at 252 lines:

| engine | before (2026-08-14 baseline) | after |
| --- | --- | --- |
| CPython 3.12 | 54.66s | 64.97s |
| pxx-compiled uforth | 153.18s | **148.00s** |
| **ratio** | **2.80x** | **2.28x** |

The two runs here were concurrent, so both absolute numbers are inflated and
**only the ratio is comparable** — the same discipline this ticket's original
table used.

**This is an honest partial result and should be read as one.** A 62.5%
cost centre going away predicts far more than 2.80x -> 2.28x, so uforth's
concatenations are largely NOT the self-append shape. Re-profiling rather than
guessing which is the next entry below.

### Provenance

Compiler at aca188198 + the variant half; pin v299 carries the Pascal half.
Every number above is from a self-hosted fixedpoint build at that tree, not
from the watcher's clone.

### Re-profiled after the fix — the concat cost centre is gone, and the ticket's remaining 2.28x is something else

Same instrument as the original profile (callgrind, addresses resolved through
the `.map`; `perf` is still unusable on this box). Subject is a driver that
INCLUDEs `prelimtest.fth` + `tester.fr` + `core.fr`, 12.1e9 Ir total. Not
directly comparable to the earlier 2.43e9 run's absolute numbers — a different
driver — but the SHARES are the point:

| function | share before | share now |
| --- | --- | --- |
| **PXXStrConcat** | **62.5%** | **6.79%** |
| PXXAlloc | 8.9% | 13.18% |
| PXXStrFromLit | — | 9.28% |
| PXXFree | 2.0% | 6.06% |
| PXXStrAppend | (did not exist) | 5.21% |
| PXXMemZero | 2.0% | 3.87% |
| PXXRecordRelease | — | 3.36% |
| pystr_isascii | 4.3% (pre-cause-A) | not in the top 20 |

So the fix did land broadly — concat fell by a factor of nine as a share of a
much larger run. **The 2.28x that remains is not concatenation.** It is
allocation churn: `PXXAlloc + PXXStrFromLit + PXXFree` = **28.5%**, and the
profile is now flat rather than having a pole.

Two follow-ups this suggests, neither started, both needing their own sizing:

1. **`PXXStrFromLit` at 9.28%** — every string literal materialises a fresh
   heap block on every evaluation. `PXX_FLAG_STATIC` is defined and unused, and
   interning or a static-block representation is the obvious shape. This is
   likely the single biggest remaining item.
2. **The byte-at-a-time copy loops.** `PXXMemMove`, `PXXMemZero`,
   `PXXStrConcat` and `PXXStrAppend` all copy one byte per iteration in Pascal.
   A word-at-a-time copy with a byte tail would help all of them at once, and
   `PXXMemZero` at 3.87% is pure copy cost.

Neither is a NilPy or a frontend question — both are shared runtime, so both
stay Track O / file-owned by A, same as this ticket.

### Status

Cause A fixed (pin v298), cause B fixed (v299 + the variant half). The ticket's
original subject — a compiled frontend losing to a bytecode interpreter — is
**improved but not closed**: 2.80x -> 2.28x with output byte-identical
throughout. Leaving this open at prio 65 with the allocation-churn diagnosis
banked is the honest state; closing it on the concat fix would misreport it.

`SLOW_SHARDS` should NOT be dismantled yet — that was conditioned on blocktest
becoming ordinary, and a 2.28x ratio is not that.

## Follow-up 2 DONE 2026-08-15 — the byte-at-a-time copy loops are now word-at-a-time

The second of the two follow-ups above. Every block copy in the runtime moved
ONE BYTE per iteration; `PXXBlockCopy` (builtinheap.pas) moves a machine word
per iteration with a byte tail, and `PXXStrConcat`, `PXXStrAppend` (both arms),
`PXXMemMove` and `PXXMemZero` all route through it.

**Alignment is the whole design constraint, not a detail.** ARM32 faults on an
unaligned word access, so the word loop runs only when BOTH ends are
machine-word aligned and the byte loop is both the tail and the fallback. In
practice the aligned case is the common one — string data sits at
`base + PXX_HDR_SIZE` with `PXX_HDR_SIZE = 24` and `base` 8-aligned, so
string-to-string copies qualify. `d + lenA` in a two-segment concat does NOT
unless `lenA` is a multiple of the word size, which is why each segment asks for
itself rather than the routine asking once. The step is `SizeOf(NativeInt)`,
never a literal 8 — a hardcoded step copied every other word on 32-bit once
already.

The ASCII scan folded in with it: the byte loops OR'd every byte and
`PXXStrMeta` reads only `orAll and $80`, so the word loop ORs whole words and
collapses through the all-bytes high-bit mask. Same answer, one operation per
word instead of per byte. `test_nilpy_non_ascii_case_and_explode` and
`test_nilpy_case_mapping_expands` are what check that, and both are green.

### Measured — A/B on one box, same tool, same corpus

`tools/uforth_bench.py`, HEAD (self-hosted fixedpoint) against
`stable_linux_amd64/default/pinned` (v321), run back to back:

| bench | pinned v321 | HEAD | gain |
| --- | --- | --- | --- |
| microbench-doloop | 14835.3 ms | 14199.2 ms | 1.04x |
| prelim | 720.6 ms | 617.8 ms | **1.17x** |
| core | 2006.5 ms | 1822.8 ms | **1.10x** |

And on a copy-DOMINATED workload — 20k `s = s + "abcdefgh"` plus 20k
`parts.append("xy" + str(i))` then `"".join` — 9.63 s -> 5.73 s, **1.68x**,
output byte-identical to CPython.

**Read that gap honestly:** 1.68x where copying dominates, 1.04-1.17x on uforth,
because uforth's remaining cost is ALLOCATION, exactly as the profile above
says. This is the smaller of the two follow-ups landing first because it is the
safer one; it does not close the ticket.

Cross-compiles clean for aarch64 / arm32 / i386 / riscv32. The alignment guard
is what makes that safe rather than lucky, and Track T's matrix is what will
prove it on hardware.

### Still open — follow-up 1, and it is the bigger one

`PXXStrFromLit` at 9.28% of the profile: every string literal materialises a
fresh heap block on every evaluation. `PXX_FLAG_STATIC` is defined and unused.
That, plus `PXXAlloc`/`PXXFree` around it, is the 28.5% this ticket is now
actually about. Not started.

### Follow-up 1 sized, NOT started — and the obvious implementation is wrong

Sized before parking, because the shape that suggests itself is unsound and
that is worth knowing before someone spends a session on it.

**The tempting version: intern inside `PXXStrFromLit`,** keyed on
`(src, len)`. A literal's source address is a stable `.rodata` address, so a
repeat evaluation would hit the cache and skip the allocation entirely — no
backend changes, all of it in `builtinheap.pas`.

**It is wrong, because `PXXStrFromLit` is not a literal-only entry point.**
Measured by reading the callers of the per-backend shim
(`AnsiStrFromLiteralAddr`, 12 call sites in `ir_codegen.inc` alone):

| call site | source it passes |
| --- | --- |
| `IR_CONST_STR` load | `.rodata` — the literal case |
| `EmitAnsiStrFromInlineString` | an inline `[len][chars]` blob |
| PChar -> AnsiString | an arbitrary pointer, heap or foreign |
| readln | the **BSS line buffer**, which is overwritten every line |
| copy of an existing managed string | a HEAP handle |

Two of those are fatal to an address-keyed cache: the BSS line buffer is
MUTATED between calls, so the cache would answer with a previous line; and a
heap handle's address is RECYCLED after free, so the cache would answer with a
dead string's contents. Both are silent wrong VALUES, which is the failure class
this repo is worst at finding.

**So the real shape is a second shim** — one used only for the `IR_CONST_STR`
load — and that is per-backend setup across six drivers, which is the recurring
landmine ([[project_call_to_code_offset_zero_is_the_elf_entry_point]] is the
same shape). Sized as its own session, not a tail-end addition.

Two facts that make the eventual implementation safe, both checked here:

- **Identity is fine.** `PXXStrUnique` copies whenever `rc > 1`, so an interned
  block with a SATURATED refcount copies on every write — `s1 := 'abc'; s2 :=
  'abc'; s1[1] := 'x'` cannot alias. `PXXStrDecRef` can never free it either.
- **`PXX_FLAG_STATIC` already exists** (builtinheap.pas:181, declared
  "reserved, unused") and is the natural stamp for "never freed, always COW".

Parked to `unfinished/` with follow-up 2 landed and follow-up 1 sized.

## 2026-08-30 — FOLLOW-UP 1 LANDED behind -O3 (x86-64). A literal is an address now

Landed and measured at `823f1c85b`; the binary those numbers came from is
sha256 `6a078478d137`. (Both citations were first written as the pre-rebase
shas out of this session's own reflog, which resolve here and nowhere else —
`tools/progress.py check` now reports that as DANGLING-SHA.)

The sizing above said the tempting implementation — interning inside
`PXXStrFromLit`, keyed on `(src, len)` — is unsound, and it is. But the "second
shim" it recommended instead is not the smallest correct answer either. **The
literal does not need a shim at all: it needs a header.**

`InternStr` now lays a managed-string header down in FRONT of every pooled
literal, so the block already IS a managed string. The three words go in
*before* `Strs[].Offset` is taken, and that is the whole trick:

```
[allocsize=0][meta][rc=2^30]  [len]  [chars...][nul]
                              ^Offset (unchanged)
                                     ^Offset+8 = the managed handle
```

`Offset` still points at the length prefix, which is exactly what every
existing consumer of the frozen inline form already reads — and that same
prefix IS the handle's `len` word at `handle-8`. **No call site changed.** The
header lives at negative offsets nobody has to know about unless they want the
handle.

x86-64 codegen then loads that address instead of calling
`AnsiStrFromLiteralAddr`: the two literal-assignment sites and the six
inline-string conversions (call args, virtual-call args, variant boxing). No
`PXXStrFromLit`, no `PXXAlloc`, no copy of bytes that are already in the image,
and no `PXXFree` when the reference dies.

### Two things it had to get right

**It has to TAKE A REFERENCE.** Every site replaced used to receive a fresh
block at `rc=1` and take ownership of it — no retain on the store, a release
when the reference dies. Handing the static block back without the increment
keeps that release, so each store/overwrite cycle walks the static refcount
permanently DOWN by one. 2^30 sounds out of reach until you price it against
this ticket's own subject: ~400s of runtime, and 2.5M literal stores a second
is an ordinary rate. So `inc qword [rax-16]` — four bytes, no call — and the
saturated start goes back to doing only the job it was chosen for, keeping
`PXXStrDecRef`'s `rc = 0` test false.

**The empty literal is not just an address.** Pascal collapses `''` to nil and
NilPy deliberately does not, so the emitter makes the same split the runtime
makes.

Every in-place mutation path was read rather than assumed, and each already
refuses a shared block for its own reasons: `PXXStrUnique` and the inlined
SetLength fast path both gate on `rc <= 1`; `PXXStrAppend` additionally requires
`PXX_FLAG_APPENDABLE`, which a static block never carries; `PXXStrDecRef`'s free
is behind `rc = 0`. The allocator's size word is written as an explicit zero
anyway — it is unreachable today, and a garbage capacity that only a future flag
change could reach is the shape this runtime has already been bitten by.

### Measured — and the first reading was the WRONG A/B

The obvious comparison is `-O2` against `-O3`, and it is wrong: `-O3` carries
every other `-O3`-gated pass too (the whole W1 register-residency set, the
last-argument collapse). That measures the tier, not the change — the same
family as the exit-status warning going round the fleet today, a layer between
the value and the reading of it, quietly answering a different question.

So the A/B is `-O3` against `-O3` **with only this pass's gate raised out of
reach**, same HEAD, same everything else. Interleaved A/B/A/B against drift,
min of the reps, on a contended box:

| subject | -O3, pass off | -O3, pass on | wall | workload only |
| --- | --- | --- | --- | --- |
| stringtest.fth | 2.215s | 1.915s | -13.5% | **-21.6%** |
| memorytest.fth | 2.016s | 1.717s | -14.8% | **-26.9%** |
| coreexttest.fth | 3.217s | 2.817s | -12.4% | **-15.7%** |
| core.fr | 5.434s | 4.927s | -9.3% | **-10.0%** |

"Workload only" subtracts the fixed prelude, measured separately with a driver
that INCLUDEs the four harness files and no word set: 1.236s → 1.147s. That
subtraction is not cosmetic — the raw deltas were suspiciously CONSTANT at
~0.3s across three subjects of different length, which is the signature of a
cost that does not scale with the thing you think causes it. It turned out the
prelude is a large shared fixed chunk and the workload gain is real underneath
it, but the constant-delta reading had to be chased before it could be trusted.

Absolute times drift run to run here (coreexttest measured 2.514s and 2.817s
for the *same binary* twenty minutes apart); the deltas are consistent in sign
and size across four subjects and two independent sittings, and that is what
the table is for.

### Correctness

- `test_static_string_literals` at -O3 with -O0 as the control, one expectation
  for both. Every row reads the literal AGAIN after mutating a copy of it, so a
  mutated static block shows up as the SECOND read being wrong. Wired into the
  Makefile and the rows were proven to run and to fail (extracted into a scratch
  makefile so real `make` did the expansion, then broken on purpose).
- Non-vacuity: `MSTR_STATIC_RC = 0` makes -O3 print `b=Zbcdef` — the static
  block edited in place — while -O0 stays correct **and the compiler still
  self-hosts byte-identically**, because it builds at the default -O level. The
  fixedpoint gate cannot see an -O3-only defect; that is stated in CLAUDE.md and
  this is another instance of it.
- Three real uforth word sets (stringtest, memorytest, coreexttest) run
  differentially at -O3: byte-identical to CPython, and identical to -O2.
- NilPy literal micro-subject byte-identical to CPython at -O0/-O2/-O3.
- A compiler built entirely through this path emits a byte-identical compiler.

### Still open

- **Promotion to -O2 is not taken here.** Per the lane rule a new pass promotes
  only after the full gate, which is Track T's sweep of this sha and not mine to
  run. The evidence for promoting is strong (a 9.5 MB self-hosting compiler
  built through the path reproduces itself byte for byte, and three differential
  corpora agree with CPython) — but it is a separate, deliberate step.
- **Five backends still call the shim.** i386, aarch64, arm32, xtensa, riscv32
  are untouched; the pool header is emitted for them too and simply unread. The
  aarch64 port is the one worth doing per the per-backend rule.
- **The ticket's own subject is not re-measured.** `blocktest` is ~240s under
  pxx plus ~80s of CPython oracle on a workstation that is somebody's desk;
  the small subjects are the proxy the ticket already established for exactly
  this reason. A blocktest number should come from T's sweep, not from here.
- `SLOW_SHARDS` still should NOT be dismantled.

## 2026-08-30 — aarch64 ported, and where the next cost is

`89ab3d9d4` ports the same pass to aarch64: one predicate and three emit sites,
because the header is in the **pool** and not in a per-backend shim, so the
representation was already shared. `EmitAnsiStringFromNodeA64` is one central
conversion where x86-64 has eight. Parity counts move together, x86-64 22→23
and aarch64 10→11 — the gap does not widen. Verified under qemu-aarch64, -O3
and -O0 byte-identical to each other and to x86-64, and the same
`MSTR_STATIC_RC = 0` break shows there too.

aarch64 takes its reference by CALLING `PXXStrIncRef` where x86-64 emits a
four-byte `inc qword [rax-16]`; a hand-emitted aarch64 retain has to reproduce
the threadsafe arm as well (LSE or ldxr/stxr) and `EmitStrIncRefA64` already
gets that right. Still a fraction of the allocate-copy-free it replaces.

### Banked, not started: PXXAlloc zeroes a span the caller is about to overwrite

Read while looking for what is left, and worth writing down before it is
forgotten. `PXXAlloc` is already O(1) — size-class bins, exact-fit head, no
walk except for the rare large blocks. What it spends its instructions on is
the **zero-init contract**: a block taken off a free bin is zeroed a machine
word at a time across its whole size before it is handed back.

For the string path that zeroing is almost entirely a double write.
`PXXStrFromLit` immediately stamps three header words and then copies `len`
bytes plus a nul over the rest — every byte of the block except the tail
padding is written twice, once with zero and once with the answer.

The shape that would fix it is the one this ticket keeps arriving at: not a
flag on the existing entry point, but a **second entry point** for callers that
provably overwrite what they are given. Note the contract is deliberately
global and the comment in `PXXAlloc` says so ("Anything that changes the bump
path ... must re-produce the guarantee here, not push it back onto callers"),
so this is an addition beside it, never a relaxation of it.

What has to be established before writing any of it, and none of it is done:

- which callers really do overwrite the WHOLE payload, tail padding included —
  `PXXStrFromLit` writes up to the nul and not past it, and the block is
  rounded up to 8, so the padding is stale under a raw alloc;
- whether anything reads that padding. Nothing should, but "should" is what
  this runtime's expensive bugs are made of, and `PXXStrAllocSize` already
  invites an appender into exactly those bytes;
- and it needs a MEASUREMENT first, which this box cannot currently give:
  `perf_event_paranoid` is 4 and valgrind is not installed, so the callgrind
  shares quoted higher up this ticket cannot be reproduced here at all. The
  numbers in the 2026-08-30 table are wall-clock A/B against a toggled gate,
  which is enough to size a change already made and NOT enough to rank two
  changes not yet made.

That missing instrument is the real blocker on the next slice, and it is a
Track A gap rather than a Track O one: this runtime has `-dPXX_HEAP_DEBUG`,
`-dPXX_OBJTRACE` and `PXXDBG` for correctness questions and nothing at all for
"how much does it allocate, and of what size". A census under its own define —
counts and a size histogram, no call-site attribution — would have answered in
one run what three sessions have reached for callgrind to learn.

### The zero-init candidate: an experiment that produced a 6x SPEEDUP and was void

Run before writing anything, to price the banked diagnosis above rather than
rank it on a hunch. The zeroing on `PXXAlloc`'s O(1) reuse path was disabled —
deliberately unsound, as a measurement only — the compiler rebuilt, uforth
rebuilt with it, and `core.fr` timed against an unpatched build at the same
HEAD, interleaved:

```
uf_zon:  min 4.443s
uf_zoff: min 0.714s      -83.9%
```

**That number is not a speedup. It is a segfault at 0.7 seconds.** 66 lines of
output became 1. The run did not get faster, it stopped doing the work.

This is the fleet's exit-status warning arriving in its predicted form — *a
silently-red configuration does not merely report success, it reports a
speedup* — and it is worth being precise about what did and did not catch it.
The exit status **was** available: `ufrun.sh` propagates the program's rc. The
timing loop threw it away, by construction:

```sh
t=$( { TIMEFORMAT=%R; time "$b" ...; } 2>&1 | tail -1 )
```

That idiom captures the timing and discards the verdict — `$?` is `tail`'s, and
even without the pipe the assignment's status is the substitution's. **A timing
harness is the one place the exit status is most load-bearing and the standard
idiom for timing is the one that drops it.** What actually caught this was the
output diff against the control run, printed BEFORE the timing loop rather than
after. That ordering was luck as much as discipline; it is now the rule for
this ticket's harness, and the loop carries the rc as well.

**The void experiment still produced a finding, and it argues against the
candidate rather than for it.** The zero-init contract is load-bearing enough
that the workload dies in under a second without it — so the redundant-write
story may be true and is certainly not the whole story, and a global switch is
off the table for real reasons rather than stylistic ones. Anything here has to
be a second entry point used by individually audited callers, which is what the
`PXXAlloc` comment already demands. Still not started, now for a measured
reason.

Note also what did NOT catch it: the compiler self-hosted **byte-identically**
with the zeroing disabled. A fixedpoint proves the compiler reproduces itself,
not that the runtime is sound.

### COUNTED at last — 44.5% of every allocation in `core.fr` is gone

Built `-dPXX_ALLOC_CENSUS` first ([[feature-a-allocation-census-define]])
rather than ranking the next candidate on a hunch, because this ticket has now
produced two bad rankings from missing instruments in one night. The census is
a counting instrument, so unlike everything else measured here it is immune to
the box being busy.

Provenance, because a measurement carries its configuration or it carries
nothing: taken at HEAD `7dbbab6a2`, compiler sha256 `dfb89430336b`, and
re-taken there after four intervening compiler builds. **The allocation totals
reproduced exactly** — 14,482,408 and 8,036,705 both times. The size histogram
moved by a handful of entries (3 in the 32-byte class, 6 in `live`), so the
right claim is *reproducible to about 1e-7 and not bit-exact*; some small
number of allocations depends on the environment the process starts in. That is
still four orders of magnitude tighter than any timing on this box.

uforth `core.fr`, same driver, `-O2` against `-O3`:

| | allocations | bytes | live | 32-byte class |
| --- | --- | --- | --- | --- |
| -O2 | 14,482,408 | 595,241,560 | 441,943 | 11,710,484 |
| -O3 | **8,036,705** | 384,315,424 | 195,746 | **5,567,269** |

**44.5% fewer allocations, 35% fewer bytes** — and the histogram says where:
the 32-byte class alone falls by **6.14M**, which is 95% of the entire
reduction and is exactly a short literal's block (24-byte header + up to 7
bytes + nul, rounded to 8). The pass is doing what it was designed to do, in
the size class it was designed to do it in, and this is the first statement
about it on this ticket that is a mechanism rather than a percentage.

It also explains why the wall-clock win is 10-25% and not 44%: halving the
allocations leaves the rest of the interpreter — the concatenations, the
dictionary walk, the inner loop — untouched, and those are now the majority.
**A halved allocation count is not a halved runtime, and the census is what
makes the difference legible instead of disappointing.**

The two figures now sit at different confidence levels and should be quoted
that way: the allocation counts are exact and reproducible on any box, the
timings are min-of-interleaved-reps on a contended workstation.

## PARKED 2026-08-30 — fleet stood down for a merge and re-pin

Moved `working/` → `unfinished/` by its owner (frank-optimize-b4) because the
fleet paused and a lock with a stopped owner is unreadable: whoever runs the pin
cannot tell it from live work. **Bookkeeping, not a rollback.**

**Nothing is half-applied.** Every change is committed and on `origin/master`,
each one gate-green when it landed: the `-O3` static-literal pass (x86-64 then
aarch64 `89ab3d9d4`), `-dPXX_ALLOC_CENSUS` (`0f0a5619a`), and the two write-ups
(`5bb3e120d`, `e61b96811`). There is nothing to revert and nothing to finish
before the tree is safe to merge or pin.

### Where it actually stands

The ticket's subject — `blocktest` at 2.1x slower than CPython — is **not
closed**. What has changed is that the two named cost centres are gone (Cause A
`s[i]` rescan, Cause B concat allocate-and-copy) and the third, string literals
allocating at runtime, is fixed behind `-O3` on the two backends the lane rule
covers. Measured effect: **44.5% fewer allocations and 35% fewer bytes** on
`core.fr`, of which 95% is the 32-byte class, i.e. exactly a short literal's
block. Wall clock moves 10-25%, not 44%, because what remains is the
interpreter's own work.

### Resume conditions, in the order they unblock

1. **`-O2` promotion of the static-literal pass — WITHHELD, and it needs Track
   T's full-tier sweep of the landing sha, not a decision here.** This is the
   single highest-value next step and it is not mine to take.
2. **The three unported backends** (i386, arm32, xtensa, riscv32) — but the
   per-backend rule says x86-64 and aarch64 only, so this is *deliberately* not
   next. Listed so nobody reads its absence as an oversight.
3. **The next cost centre is unranked, and that is on purpose.** This ticket
   produced *two* bad rankings from missing instruments in one night, which is
   why `-dPXX_ALLOC_CENSUS` exists. Whoever picks it up: **count before you
   rank.** The census is exact and box-independent; every timing on this ticket
   is min-of-interleaved-reps on a contended workstation and they are not the
   same kind of number.

### Two traps banked here, both already paid for once

- **`PXXAlloc`'s zero-init is NOT the next win.** The experiment that priced it
  reported **−83.9%** and was a **segfault at 0.7 s** — the run did not get
  faster, it stopped doing the work. A global switch is off the table for
  measured reasons. Anything here must be a second entry point with individually
  audited callers. Note also what did not catch it: the compiler self-hosted
  **byte-identically** with zeroing disabled. *A fixedpoint proves the compiler
  reproduces itself, not that the runtime is sound.*
- **`SLOW_SHARDS` still must NOT be dismantled.**

### Do not resume by re-measuring `blocktest` on this box

It is ~240 s under pxx plus ~80 s of CPython oracle on somebody's desk. The
small subjects are the established proxy, for exactly that reason. A `blocktest`
number should come from Track T's sweep.

---

## CORRECTION to the section below — I appended it without reading this ticket

Written after the fact, by the same session (frank-optimize), and placed above
its own work on purpose. **I read this ticket's first ~40 lines, ran an
independent investigation, and appended the result to the end of a 1193-line
file.** Several of the conclusions below were already established here, by
sessions on 2026-08-14, 08-15 and earlier on 2026-08-30, using **callgrind** —
a better instrument than the one I built. The section below does not say so,
because I did not know.

**What was already in this ticket and is NOT a finding of mine:**

| my section says | already here, since |
| --- | --- |
| "96% of samples in the RTL, no dominant peak" | 2026-08-14/15 §"Re-profiled after the fix": `PXXAlloc + PXXStrFromLit + PXXFree` = 28.5%, *"the profile is now flat rather than having a pole"* |
| "the cause is allocation and copy traffic, not one hot spot" | same section, stated in those words |
| "every string literal materialises a fresh heap block per evaluation" | §"Follow-up 1 sized, NOT started", with `PXX_FLAG_STATIC` already named as the fix — and then **LANDED behind `-O3` earlier the same day** (§"FOLLOW-UP 1 LANDED") |

I re-derived the third one from a disassembly and was about to file it as a new
ticket. It is fixed. Measured just now, marginal cost of `x = "k"` in a loop:
**-O2 80.3 ns, -O3 0.0 ns** — the pass works, and I would not have spent the
time had I read to line 586.

**What IS new from this session, after that subtraction:**

1. **A working allocation counter, which this ticket named as its blocker.**
   §"Still open" says: *"it needs a MEASUREMENT first, which this box cannot
   currently give: `perf_event_paranoid` is 4 and valgrind is not installed…
   A census under its own define — counts and a size histogram — would have
   answered in one run what three sessions have reached for callgrind to
   learn."* A gdb breakpoint on the allocator entry, differenced between
   n=1000 and n=3000 so startup allocations cancel, gives exactly that as
   **allocations per operation** — sharper than a percentage share, because it
   attributes to a source construct rather than to a routine:

   | statement | allocs/iter |
   | --- | --- |
   | `x = 7`, `x = o.f`, `len(b)`, `isinstance`, `o.m(1)` | 0 |
   | `x = b[2]`, `x = s[0]`, `st.append(1)` | 1 |
   | `x = d['k']` | 2 |

   Cost tracked that count at ~190 ns per allocation. It also **falsified** my
   own model: `o.m(1)` costs ~390 ns with **zero** allocations, so the call
   family is a second, independent driver (per-call managed-slot init, ~50-130
   ns per argument or local) and not allocation at all.

2. **One specific allocation found and removed** — `PyVarSlotSet`'s
   unconditional `s := ''`, which every variant slot copy executed. List
   subscript 1 → 0 allocations, −41% wall clock (`c8e1a2f0`-adjacent commit).
   Prior work established the aggregate; this is a named site deleted.

3. **`PXXHighBits`** (5.1% of a sampled uforth profile) — not previously in
   this ticket.

4. **The three eliminations by intervention** (arithmetic, threading dispatch,
   `exec`/pyeval) — each built and measured to do nothing. Prior sections
   eliminated concat and `s[i]` rescan; these three are different candidates.

5. **The stale-ratio finding** — the pxx half did not move and CPython's did.

**Why this is worth writing down rather than quietly fixing.** This ticket is
1193 lines and holds four sessions of work. Appending to the end of it without
reading it is how the same ground gets re-measured, and I did it while holding
the ticket. The `PXX_FLAG_STATIC` follow-up sat at line ~543 as prose in a long
body; that it was both *already sized* and *already landed* was invisible to me
until I went looking for something else. If there is a process lesson it is the
one this ticket's own §"Still open" already makes about instruments: **read the
ticket you are holding, all of it, before adding to it** — and a long ticket is
an argument for splitting it into children, which is what the umbrella
conversion has since done.

---
## Diagnosis, 2026-08-30, frank-optimize

**Everything above this line is from `96b4b40ab` and does not survive
re-measurement.** What follows was measured at HEAD `0604b414089f`, self-hosted
fixedpoint binary sha256 `883476f0abaf` (confirmed different from `pinned`
`abece5150983`), on a box whose 1-minute load is recorded beside every number.
CPython here is **3.14.4**.

### 1. The ratio moved, and NOT because pxx got faster

| word set | ticket (`96b4b40ab`) | HEAD `0604b414089f` |
| --- | --- | --- |
| `blocktest.fth` | 413.3 / 196.0 = **2.1x** | 252.4 / 152.0 = **1.66x** |
| `core.fr` | 8.1 / 2.5 = 3.2x | 4.48 / 1.85 = 2.42x |
| `coreexttest.fth` | 6.0 / 1.9 = 3.2x | 3.45 / 1.46 = 2.36x |
| `coreplustest.fth` | 4.8 / 1.5 = 3.2x | 2.50 / 1.04 = 2.40x |
| `stringtest.fth` | 4.2 / 1.1 = 3.8x | 2.25 / 1.01 = 2.23x |
| `memorytest.fth` | 3.7 / 1.3 = 2.8x | 2.20 / 1.05 = 2.10x |

All differentials still `same`. The ratio improved by ~30% — and **the pxx half
did not move**. The Makefile's own uncontended note is ~240s pxx against ~80s
CPython; my pxx half (252s) matches that within contention noise, while the
CPython half nearly doubled (80 → 152). At least one half moved for
environmental reasons — Python 3.14.4, and a different box from the ticket's
"12-core plexus".

A ratio is the most attractive kind of stale number because it looks
self-normalising and is not. **Both halves have to be re-run.**

### 2. Three plausible causes, each eliminated by intervention

Not by argument — by building the change and measuring that it did nothing.

**(a) Integer arithmetic / the promotable-int runtime. Eliminated.**
NilPy ints are `PXXPromo*` slots and `x = a + b` was costing **1051 ns** per
operation, against 52 ns for `x = a + 1`. Cause found and fixed (`0c3ad8a10`):
the promo-with-promo entry points name `TBig` in their own bodies, so every call
pays managed prologue/epilogue for bignum temps it never builds, while the
`*Int` forms had that split out years ago. `PXXPromoAdd` 1051 → 62 ns, `Mul`
1727 → 72 ns, a bare loop 348 → 117 ns/iteration.

**uforth moved 0–5%.** Same binaries, back to back, load 1.69 → 1.93:

| | pxx before | pxx after | CPython |
| --- | --- | --- | --- |
| `core.fr` | 4.48 | 4.48 | 1.85 |
| `coreexttest.fth` | 3.48 | 3.39 | 1.47 |
| `coreplustest.fth` | 2.50 | 2.52 | 1.04 |
| `stringtest.fth` | 2.33 | 2.26 | 1.01 |
| `memorytest.fth` | 2.20 | 2.08 | 1.04 |

A 17x improvement to integer arithmetic buys nothing here. uforth's inner loop
is not arithmetic-bound. (The fix is still worth having on its own terms.)

**(b) Attribute + subscript traffic in the threading loop. Eliminated.**
`run_forth_word`'s loop reads `frame.body[frame.ip]` and `len(frame.body)` per
token, and subscript is pxx's worst measured primitive (below). Hoisting `body`
and `nbody` into locals in a copy of `uforth.py` changed nothing: 3.45 → 3.53,
2.12 → 2.14, 2.06 → 2.02 (identical output). Load 3.19 → 4.84, so the noise
floor here is wider than the effect.

**(c) `exec()` / the pyeval runtime interpreter. Eliminated.**
uforth implements its Forth primitives as Python source strings that are
`textwrap.dedent`-ed, wrapped in a `def`, and **`exec`-ed from scratch on every
single invocation** — 5643 times for `coreexttest.fth` alone. Under pxx that
runs through `compiler/builtin/pyeval.pas`, a tree-walking interpreter, so this
looked like the whole answer.

It is not. At uforth's own call count, `exec(wrapper, {}, ns)` plus the call:

| | pxx | CPython 3.14.4 |
| --- | --- | --- |
| `dedent` + wrapper build | 20.6 µs/call | 6.8 µs/call |
| `exec` + call | **68.8 µs/call** | **74.9 µs/call** |

**pxx's `exec` is slightly faster than CPython's.** Caching the wrapper string
(so `dedent` runs once per distinct body) bought pxx 9% and is the only part
worth anything. Caching the compiled function — which cuts CPython from 1.46s to
0.57s, i.e. `exec` is ~60% of *CPython's* runtime — cannot be measured under pxx
because pyeval hits two limits doing it; see §5.

### 3. Where the time actually is

`perf` is unavailable on this box (`perf_event_paranoid=4`) and I did not ask
for it to be relaxed. Instead: compile with `-g`, run under `gdb` with
`startup-with-shell off` and `handle SIGINT stop nopass`, and interrupt the
inferior on a timer, recording `$pc`. 593 samples across five word sets. `$pc`
is mapped to a function by taking the greatest call-target address ≤ `$pc` (1075
entry points recovered from the binary's own disassembly), and to a source line
via `.debug_line`.

> **4% of samples are in code compiled from `uforth.py`. 96% are in the RTL, and
> 67% are in the first 130 KB of `.text` — the string, header and heap core.**

Top routines, identified by reading their bodies (the RTL carries no symbols):

| samples | % | cum | routine |
| ---: | ---: | ---: | --- |
| 73 | 12.3% | 12.3% | allocator entry — clamps size to ≥8, rounds up to 8 |
| 45 | 7.6% | 19.9% | free path (`p ≠ nil`, read `[p-8]`, bucket) |
| 36 | 6.1% | 26.0% | string size/offset computation |
| 30 | 5.1% | 31.0% | block / ASCII string copy |
| 30 | 5.1% | 36.1% | **`PXXHighBits`** — see below |
| 25 | 4.2% | 40.3% | pyeval (`exec`, `uforth.py:1289`) |
| 20 | 3.4% | 43.7% | managed-slot init (called from every `def` prologue) |
| 10 | 1.7% | 52.1% | managed release: decref, free at zero |

134 distinct routines were sampled; the tail is long. Walking the hot entries up
the call graph, their callers are `def …` and `return …` lines spread across the
whole program — i.e. **function prologues and epilogues**, not any one hot spot.

**`PXXHighBits` deserves its own line.** `builtinheap.pas:1608`:

```pascal
function PXXHighBits: Int64;
var i, m: Int64;
begin
  m := 0;
  for i := 0 to SizeOf(NativeInt) - 1 do
    m := (m shl 8) or $80;
  PXXHighBits := m;
end;
```

It computes the constant `$8080808080808080` with an eight-iteration loop, and
is called per word of every string scan (`builtinheap.pas:1633`). **5.1% of
uforth's entire runtime is spent recomputing a compile-time constant.**

### 4. Why the ratio is only ~2.3x when the primitives are 15x apart

This is the part that makes the ticket's framing misleading, and it is why there
is no single hot spot to point at. Marginal cost of one added statement in a
NilPy loop, 300k iterations, load 2.05 flat across the run:

| operation | pxx | CPython | ratio |
| --- | ---: | ---: | ---: |
| `b[2]` list subscript | 234 ns | 12 ns | **19.2x** |
| `d['k']` dict subscript | 495 ns | 30 ns | **16.5x** |
| `f.body[f.ip]` | 492 ns | 33 ns | 15.0x |
| `s.append` + `s.pop` | 654 ns | 76 ns | 8.6x |
| call with 8 locals | 511 ns | 120 ns | 4.3x |
| `tok.word` attribute | 57 ns | 10 ns | 5.5x |
| call with 1 arg | 129 ns | 40 ns | 3.2x |
| `vm.push` + `vm.pop` | 780 ns | 237 ns | 3.3x |
| `exec` + call | 68.8 µs | 74.9 µs | **0.92x** |
| `isinstance(t, (int, float))` | 62 ns | 158 ns | **0.39x** |
| `isinstance(t, int)` | 47 ns | 64 ns | 0.73x |
| `len(b)` | 3 ns | 24 ns | **0.14x** |
| call, no args, no locals | 3.5 ns | 37 ns | **0.10x** |

pxx is 15-19x slower at container subscript and 2-10x **faster** at `isinstance`,
`len`, `exec`, and a zero-argument call. From `cProfile` on the same workload,
`isinstance` is 10% of CPython's time, `len` 5%, `exec` 15% — 30% of the
reference's runtime sits in operations pxx wins. That is precisely why a program
built from primitives that are individually 15x apart comes out only 2.3x apart
overall, and why **no single fix will close this gap**.

The one structural statement that does hold: a call with no arguments and no
locals costs 3.5 ns, and each argument or local adds 50-130 ns. Every NilPy
local is a managed slot initialised and finalised per call. That, plus the
allocator and free paths above, is the shape of the 96%.

### 5. Filed separately

- `bug-a-managed-temps-for-an-untaken-branch-are-still-init-and-finalized` —
  the codegen cause behind `0c3ad8a10`. Splitting routines by hand is a
  workaround that `promocore.pas:796` institutionalised; sinking temp init into
  the branch that uses it fixes every program. Also: a 16-byte managed clear is
  emitted as `rep stosb`, 21 of them in one prologue.
- `bug-a-pxxhighbits-recomputes-a-compile-time-constant-in-a-loop` — 5.1% of
  this workload.
- `bug-n-a-function-created-by-exec-loses-its-globals-when-it-outlives-the-call`
  and the `pyeval: no RTTI for attribute vars` refusal — both are CPython
  programs pxx cannot run, so both are N bugs by the upward-compatibility rule,
  not compat items.

### 6. What this ticket should become

The measured cause is **not** threading dispatch (pxx beats CPython at it), not
refcount traffic on stack words, not the arithmetic, and not `exec`. It is
**per-call managed-slot init/finalize plus allocator and string-header traffic
in the RTL**, spread thin across 134 routines with no dominant peak, and it is
partly offset by real wins elsewhere.

That makes this a **campaign, not a bug**: container subscript (19x, the worst
single primitive and the most clearly fixable), the managed-temp codegen ticket,
`PXXHighBits`, and the allocator's cost per call. Recommend re-filing as those
four and closing this one, rather than leaving a p65 "uforth is slow" ticket
that no single change can resolve.

**Not done here:** `blocktest.fth` itself was not re-run after `0c3ad8a10` — an
~800s pair, and this box had three other agents gating, csmith running and a
multi-hour refactor starting. The short word sets are the evidence above; a
quiet-window `blocktest` pair is worth taking before anyone quotes a new ratio.

---

## Converted to an UMBRELLA, p65 -> p25 (coordinator, 2026-08-30)

**Not closed, and not left ranked as a bug.** frank-optimize delivered a measured
cause at HEAD `0604b414089f` (binary `883476f0abaf`, confirmed != `pinned`) and
recommended re-filing as its four children and closing this. The children are
filed; this stays as the aggregate, because a bug ticket and an umbrella fail
differently:

- Left at **p65 `type: bug`**, the ranker keeps offering it as though a single
  change closed it. **No single change does** — that is this ticket's finding.
- **Closed**, the aggregate signal disappears: "pxx runs this real program ~2.3x
  slower than CPython" is worth tracking even with no single fix, and nothing
  else in the tree records it.

An umbrella at p25 says both: real, tracked, and **not a unit of work** — spin out
a rung, do not claim this.

### Both numbers in the original table are dead — and not for the same reason

```
blocktest ratio  2.1x -> 1.66x
  pxx half     ~252s   — UNCHANGED (matches the Makefile's own uncontended ~240s note)
  CPython half   80s -> 152s   under Python 3.14.4
```

**The ratio "improved" because the reference got slower.** The oracle changed
under us — a Python upgrade — and a ratio is exactly the shape that hides it,
since the number moves in the direction that looks like progress. Neither half
survives; both need re-running together in a quiet window.

**Nothing here was re-measured against `blocktest` after `0c3ad8a10`** — an ~800s
pair on a box with four sessions compiling. Every figure below it is from the
short word sets, run back to back with the load recorded. **Do not quote a new
blocktest ratio until someone gets a quiet box.**

### Why there is no hot spot, as a number

593 gdb samples across five word sets (`perf` unusable — `perf_event_paranoid=4`,
deliberately not relaxed): **4% of samples in code compiled from `uforth.py`, 96%
in the RTL**, 67% in the first 130KB of `.text`. Allocator 12.3%, free 7.6%,
string size/offset 6.1%, block copy 5.1%, `PXXHighBits` 5.1%, pyeval 4.2%. 134
routines, long tail, no peak.

pxx is **19x slower at list subscript and 16x at dict subscript** — and **2.6x
faster at `isinstance`, 7x faster at `len`, 10x faster at a bare call, level at
`exec`**. cProfile puts 30% of CPython's runtime in operations pxx *wins*. That
is why primitives 15x apart yield a program only 2.3x apart, and why no single
change closes it.

### Three hypotheses eliminated by INTERVENTION, not argument

Each was built and measured to do nothing — which is why they are eliminated
rather than deprioritised:

| hypothesis | intervention | result |
| --- | --- | --- |
| arithmetic | fixed a real 17-24x promotable-int cost (`0c3ad8a10`) | **uforth moved 0-5%** |
| threading dispatch | hoisted per-token attribute reads out of `run_forth_word` | 3.45 -> 3.53, nothing |
| `exec`/pyeval (5643 execs per word set) | measured `exec`+call | 68.8us pxx vs 74.9us CPython — **pxx wins** |

The arithmetic fix is worth having on its own and is not this ticket's answer.

### Children

- [[bug-a-managed-temps-for-an-untaken-branch-are-still-init-and-finalized]] (A p55)
  — the codegen cause behind `0c3ad8a10`; isolated 44x repro, 20M calls,
  0.294s vs 13.060s, identical semantics, same never-taken branch.
- [[feature-opt-nilpy-container-subscript-is-15-19x-slower-than-cpython]] (O p55)
- [[bug-a-pxxhighbits-builds-a-constant-with-an-eight-iteration-loop]] (A p50) —
  `builtinheap.pas:1608` builds `$8080808080808080` with a shift/or loop, per
  machine word of every string scan: **5.1% of total runtime, more than all of the
  user's compiled code.** Fix is a per-width `const`, not a literal — the loop
  exists to be right on 32-bit.
- [[bug-n-exec-only-publishes-a-def-named-body]] (N p45) — and see below.

### One child is a guard that cannot fire

`pyeval.pas:5748` publishes exactly one def into the caller's namespace: one
literally named `__body__`, hand-wired to uforth's idiom. `exec("def body(): return
1", {}, ns); ns["body"]()` raises `KeyError` under pxx and prints `1` under
CPython. The comment beside it calls the next loop "the general case" — but that
loop publishes *bindings*, and a def is not one.

**uforth cannot fail on this: it is the program the special case was written
from.** So the existing coverage is structurally incapable of catching it, and no
amount of running uforth ever will. That warning is in the child ticket.
