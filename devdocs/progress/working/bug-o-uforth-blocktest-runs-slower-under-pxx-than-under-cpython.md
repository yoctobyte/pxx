---
summary: "uforth's blocktest word set takes 413s compiled by pxx against CPython's 196s interpreting the same source — the AOT compiler is 2.1x SLOWER than the interpreter it is differentially tested against, and it is now the pole of two test tiers"
type: bug
track: O
prio: 65
status: working

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
