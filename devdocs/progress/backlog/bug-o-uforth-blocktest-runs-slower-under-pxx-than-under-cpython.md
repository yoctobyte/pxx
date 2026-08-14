---
summary: "uforth's blocktest word set takes 413s compiled by pxx against CPython's 196s interpreting the same source — the AOT compiler is 2.1x SLOWER than the interpreter it is differentially tested against, and it is now the pole of two test tiers"
type: bug
track: O
prio: 65
status: open

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
