---
track: A
prio: 85
type: perf
blocked-by: []
summary: "The structural half of bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost, which halved the constant (8.62s -> 4.06s) by removing the hotspots but did NOT remove the WORK: every .npy compile still parses and code-generates all 24,460 lines of pylib.pas + pyeval.pas before it looks at the user's program. A zero-byte .npy costs 4.06s where `begin end.` costs 0.24s."
status: done
owner: agent-A-npytax
---

# Every `.npy` compile still rebuilds the whole NilPy runtime from source

Successor to **`bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost`**
(resolved 2026-08-26). That ticket found four hotspots inside the shared
codegen and removed them — the constant went **8.62s -> 4.06s, byte-identical
output, no coverage given up**. Read its RESOLVED section before starting here;
in particular its list of things that are already ruled out, so they are not
re-hunted.

What it did **not** do is remove the work. The injection is still unguarded:

```
compiler/pyparser.inc:34707    ParseUsesUnitAmbient('pylib');
compiler/pyparser.inc:34708    ParseUsesUnitAmbient('pyeval');
```

so `pylib.pas` (18,768 lines) and `pyeval.pas` (5,692 lines) are parsed and
code-generated on **every** invocation, before the user's source is looked at.
A **zero-byte** `.npy` costs 4.06s; `begin end.` in Pascal costs 0.24s.

## What is and is not still true

Still true, from the original diagnosis:

- flat in program size (an empty `.npy` and a real test land within noise);
- compute, not I/O;
- **DCE is not the lever** — it refuses on NilPy outright, and where it does run
  it cuts 34% of emitted code for ZERO wall-clock saving, because `dce.inc` is a
  post-pass and the compiler emits each routine as it parses it.

No longer true, and the reason this ticket exists at a lower prio than its
parent:

- "the compiler compiles the NilPy runtime at the same throughput it compiles
  itself, ~4 s/MB" — it is now ~1.8 s/MB, and the four fixes moved every
  frontend with it.

## The three options, re-costed

**Fix A — serialise/cache the compiled runtime unit image.** Still the only
route to ~0.3s. Still the same risk profile: the compiler has no unit-image
serialisation, emission is fused with parsing into one global `Code[]` plus
global `Procs`/fixup/RTTI/`UCls` tables, and the sharp edge is cache
invalidation — miss a key (a define, the target, an `-O` level) and the compiler
silently emits stale code. A conservative first cut keys on the full flag set
and refuses the cache on any unrecognised flag.

**Fix B — do not pull `pyeval` unless the program can reach it.** The cheapest
real slice, and the one to try first. The precedent is next door: `math` is
pulled only when the token scan sees `**`. `pyeval` is 5,692 of the 24,460
runtime lines. **Owned by Track N** — the two call sites are `pyparser.inc`'s —
so file/hand off rather than editing it under A. The hazard is documented in
`pyparser.inc` itself: *"the LAST unit named wins a name"*, so changing pull
order silently changes which `abs`/`min`/`max` a program resolves to. Verify
byte-identically against a program that does use `eval`.

**Fix C — lazy emission.** Rejected in `dce.inc`'s header ("means replaying
parser state per routine, per frontend") and bounded by the dead fraction, ~34%.

**Recommendation: B as the shippable increment (measure it first — if `pyeval`
is reachable from `pylib` the win is zero), A as the real fix, C is a trap.**

## Repro

```
: > /tmp/empty.npy
printf 'begin end.\n' > /tmp/tiny.pas
time ./compiler/pascal26 /tmp/empty.npy /tmp/o     # ~4.1s, 1780 procs, 2,231,705B code
time ./compiler/pascal26 /tmp/tiny.pas  /tmp/o     # ~0.24s
```

Gate when fixed: `make compiler/pascal26` (byte-identical fixedpoint) + the two
timings above re-measured in the resolve note, plus a byte-identical check of a
program that DOES use whatever was made conditional.

## Track T: what this costs the MATRIX (measured 2026-08-26, pxx-aa)

Filed here rather than as a new ticket — T owns the tool, never the bug. The
numbers are the tooling side of the same defect, and they are the reason this
ticket's `prio: 45` understates it.

### The tax is the whole job, not part of it

Measured at HEAD, i.e. **after** the hotspot fixes, on this box:

| compile | wall |
| --- | --- |
| `begin end.` (Pascal) | **0.25s** |
| `int main(void){return 0;}` (C) | **0.44s** |
| zero-byte `.npy` | **4.49s** |
| `test/test_nil_python_core.npy` — a real test | **4.59s** |
| `test/lib_mimic_xml_etree_elementtree.npy` — 288 lines, the biggest | **5.58s** |

A real NilPy test costs 4.59s against an empty file's 4.49s. **The test content
is free; the fixed tax is essentially the entire job.** One frontend pays ~4.2s
that no other frontend pays, for an empty file.

Isolating the units: a *Pascal* program whose whole body is `uses pylib;` costs
**2.93s**. So ~2.7s of the tax is `pylib.pas` (18,996 lines) alone, before
`pyeval.pas` (5,733) and the frontend's own setup.

### It is the largest single block in the matrix

`test-nilpy` is **719 of the full tier's 3,063 jobs (23%) and 70% of its CPU**,
mean 15.2s per job in the watcher's learned metrics. Paying the ~4.2s tax
**once** instead of 719 times removes **~3,016 CPU-seconds**. Against the
pre-hotspot-fix matrix that is 24%; against what remains after those fixes it is
a larger fraction still, because the fixes shrank the denominator too. The next
full tier at HEAD gives the real figure and I will append it rather than
extrapolate further.

### The scheduler is NOT the problem — a deliberate negative result

Same run: 12,319 CPU-seconds against 13,663 core-seconds available (2277s wall
× 6 cores) = **90% utilisation**. There is no meaningful parallelism to reclaim,
no serialisation to unpick, and ~1,343 idle core-seconds is close to the floor
for a job graph with dependencies. **Anyone optimising the matrix should not
start with the scheduler**, and I would rather record that than have the next
person measure it again.

### Why the tooling side cannot fix it

`--help` offers no precompiled-unit or unit-cache facility: `-Fu` adds a *search
root*, not a cache. So every invocation compiles those 24,729 lines from source
and there is nothing testmgr can do about it — a test harness cannot share an
artifact the compiler has no way to emit or consume. This ticket is the fix;
there is no tooling workaround to build in the meantime.

### The prio note

The owner's loudest standing complaint is that testing overhead is ~95% of
development time. This is the single largest identified block of pure repeated
work in the matrix, it costs no coverage to remove, and it is 4.2 seconds on
every NilPy user's hello-world as well. `prio: 45` looks low against that;
raising it is the coordinator's call, not T's, so this is a flag rather than an
edit.


## Re-prioritised 45 -> 85 by the coordinator, 2026-08-26

Track T measured this from the harness side and flagged the field rather than
editing it. Raising it, on the measurement and not on the opinion.

**It is ~70% of the test matrix.** `test-nilpy` is 719 of the full tier's 3,063
jobs -- 23% of the count, **70% of the CPU**. And the tax is not part of a NilPy
job, it IS the job: at HEAD, after the hotspot work, a zero-byte `.npy` costs
4.49s and a real 288-line test costs 5.58s. **The test content is nearly free.**
A Pascal program whose whole body is `uses pylib;` costs 2.93s, so ~2.7s is
`pylib.pas` (18,996 lines) before `pyeval.pas` or any frontend setup.

Paying that once instead of 719 times is **~3,016 CPU-seconds per full tier, at
zero coverage cost** -- and the same 4.2s lands on every NilPy user's hello-world,
so this is not only a test-harness concern.

**Peer of `feature-opt-o3-register-pressure`, also 85.** Between them they are
most of the matrix cost. The order between the two does not matter; both sit
below live segfaults and wrong-value bugs, which stay the owner's top rank.

**Why it is Track A's and cannot be worked around in the harness:** the compiler
offers no precompiled-unit or unit-cache facility -- `-Fu` adds a *search root*,
not a cache. A harness cannot share an artifact the compiler has no way to emit
or consume. Track T looked, found nothing to build on, and declined to invent
something that would look like progress. T owns the tool, never the bug.

**Recorded so nobody re-measures it: the scheduler is NOT the problem.** Same
run, 12,319 CPU-seconds against 13,663 core-seconds available (2277s x 6 cores)
= **90% utilisation**, ~1,343 idle core-seconds, near the floor for a job graph
with dependencies. There is no serialisation to unpick and no parallelism to
reclaim. Do not start with the scheduler.

---

## RESOLVED (2026-08-26, agent-A-npytax) — 5.36s -> 3.06s, and the output halved

**Binaries every number below came from.** OLD = `compiler/pascal26` self-hosted
at **`cd5a3aaf8`** (= `origin/dev` at session start), built here by `make
bootstrap`, its own `cmp` fixedpoint passed, then re-emitted at an explicit
`-O2` — byte-identical to the default build, which is how it was confirmed to be
the real shipping configuration and not a debug artifact. NEW = `compiler/pascal26`
self-hosted at **`13e196cc8`**. Both were re-timed **side by side, interleaved,
in the same minute**, and the box was carrying the Track T watcher plus two other
agents throughout (loadavg quoted per table).

| workload | OLD (cd5a3aaf8) | NEW (13e196cc8) | |
| --- | --- | --- | --- |
| zero-byte `.npy` | 5.46 5.36 5.49 | 2.97 3.06 3.08 | **-44%** |
| ...user CPU | 5.18 5.27 5.19 | 2.87 2.90 2.92 | **-44%** |
| `test_nil_python_core.npy` | 5.31 5.18 5.32 | 3.08 2.85 3.00 | **-44%** |
| `lib_mimic_xml_etree_elementtree.npy` (288 lines) | (T's 5.58) | 3.67 3.85 3.70 | **-33%** |
| `uses pylib;` (pure Pascal) | 3.14 3.17 3.28 | 2.17 2.09 2.12 | **-34%** |
| `begin end.` | 0.31 0.32 0.32 | 0.27 0.31 0.26 | (never the problem) |
| **emitted code, zero-byte `.npy`** | **2,234,914 B** | **1,241,361 B** | **-44.5%** |
| `compiler.pas` self-compile | 25.70 24.38 | 22.31 21.30 | **-13%** |

loadavg 8.15 for the compile table, 17.12 for the self-compile pair.

That last row is `make compiler/pascal26` — the mandatory step in every agent's
per-fix loop on every track. The code row is every NilPy binary anyone ships.

### Where the time actually went — and the measurement that nearly went wrong

`perf` is refused here and gdb cannot attach, so this used `tools/pxxprof`
(committed by the previous Track O session; it did not compile — `open()` with
no `<fcntl.h>` — fixed in the first commit) plus FPC `-pg`/gprof for **call
counts**, which are ours where gprof's percentages are FPC's.

**Two traps first, because both produced a confident wrong reading:**

1. **`make pxx-debug` does not profile the shipping compiler.** `compiler.pas`
   line 1536: `if DebugInfo and not OptLevelExplicit then OptLevel := 0`. So
   `-g` silently means `-O0`, and the default is `-O2` (`compiler.pas:739`).
   The first profile was of a **-O0** binary and mis-weighted everything. The
   fix is `-O2 -g` explicitly — that binary's code section is byte-identical in
   size to the plain default build (9,126,147 B), which is how it was confirmed
   to be the right one.
2. **pxxprof's "outside .text / vdso" bucket is not time.** Its own header warns
   the share swings 8-38%; it hit **70%** in one run and **0.9%** in the next of
   the *same* binary, and the address moved with ASLR (`75522eaa642c` ->
   `73d5a58a642c`). `/usr/bin/time` says the compile is `user=4.92` of
   `wall=5.08`, i.e. pure user CPU. Exclude the bucket, renormalise on in-.text
   samples, and never quote a percentage that includes it.

Profile of the **real -O2 compiler** on a zero-byte `.npy` (55,127 in-.text
samples), before the fixes:

| | share of in-.text |
| --- | --- |
| builtin runtime blob range (heap alloc/free, ansistring retain/release) | **48.1%** |
| the text assembler (`AsmText*` + its share of `CaseEqual`) | **~13.2%** |
| parse + lex | ~13.9% |
| IR lowering | ~4.2% |

Answering the question this ticket was dispatched with — *parse, type-check,
lower, or emit?* — the pre-fix answer was **neither parse nor lower: emit, plus
the allocator traffic that emitting generated.** Two concrete causes, both
fixed, neither of them the Fix A/B/C the ticket nominated.

### Cause 1 — the heap allocator divided by 8 with a 64-bit `idiv` (`1202429f4`)

Three single instructions were **11.4% of all in-.text samples**:

```
4.04%  0x40098f   ((size + 7) div 8) * 8    PXXAlloc round-up
3.75%  0x4009d3   Integer(size div 8) - 1   PXXAlloc bin index
3.58%  0x400edb   Integer(sz   div 8) - 1   PXXFreePush bin index
```

Each a ~25-40 cycle `idiv` preceded by `test rcx,rcx; jne` — a runtime
zero-divisor check on the literal 8. The constant-divisor strength reduction
that folds these **already exists** in `ir_codegen.inc`, but gates on
`OptLevel >= 3`, and both the compiler and everything it emits are built at the
**-O2 default**. So the idivs ship in every pxx binary's allocator, on every
target.

Fixed at the source (`(size + 7) and not 7`, `size shr 3`) rather than by
promoting the pass — every site is guarded non-negative on the line above, and
the two forms were checked against `div` over 40,001 consecutive values and near
2^63, under both pxx and FPC. The pass promotion is the general fix and is filed
separately as **`perf-o-promote-constant-divisor-strength-reduction-to-o2`**,
because promoting an `-O3` pass needs the full gate, which is Track T's.

**-17% user CPU on its own.**

### Cause 2 — one inline helper was 99% of the text assembler (`13e196cc8`)

`EmitVariantClear` spliced its ~96-byte body in at **every** site. On a
zero-byte `.npy` that is **9,859 sites** (plus 848 for `EmitVariantRetain`):

- **~946 KB of the 2.23 MB output — ~42% of every NilPy binary was one blob**;
- and because the body is written through the readable text assembler,
  **138,026 of the compiler's 139,657 `AsmTextLine` calls**, each re-parsing
  instruction text and issuing ~36 `CaseEqual`. `EmitVariantClear` alone made
  78,872 of the 93,791 `EmitAsmX64` calls.

This is `normalise-dont-special-case.md`'s exact shape, not a new idea: **four**
managed-payload helpers, two already out of line (`AnsiStrRetain/Release`,
`ObjRetain/Release`), two left inline — and the two left inline are the ones
that stayed expensive. The bodies now emit once, from `EmitVariantBlobs` at the
tail of `EmitAnsiStringRuntime`, and the call sites are `IREmitCodeCall`.

Placing them there is **exactly as conditional as the status quo**: the bodies
already called `AnsiStrReleaseAddr` and `ObjReleaseBlobAddr`, so anything that
could reach them had already run that emitter, and `IREmitCodeCall`'s `addr = 0`
guard turns a missed one into a compiler error instead of a jump to the ELF
entry point.

### Why "the body is unchanged" is checked, not asserted

Disassembling the first body out of the OLD output and out of the NEW one, the
first 99 bytes are **identical except at offsets 65-67 and 79-81** — the two
`call rel32` displacements, which *must* differ because the blob sits at a
different code offset — and byte 99 is where the old output runs on into its
caller while the new one has `c3`. Occurrences of the body's opening
`push rax; mov rcx,[rax]`: **10,707 -> 2**, matching 9,859 + 848 exactly.

So the only semantic delta is the `call`/`ret` pair and the 8 bytes of return
address. Everything else is placement.

### Verification

- `make compiler/pascal26` byte-identical fixedpoint on every commit (2 rounds
  for the emitted-code change, as such a change must take; 1 round after).
- `tools/gate.sh quick` GREEN, twice.
- `tools/pydiff.py probe` — **14/14 agree with CPython**.
- 35 named NilPy tests matched their `.expected`, chosen for variant lifetime:
  variant fields, augmented assignment to variants and to variant subscripts,
  closures and escaping closures, `del`, exception flow, object reclamation.
- **Differential, old compiler vs new compiler, same source, outputs compared:**
  18/18 Pascal variant tests identical, 30/30 diverse NilPy tests identical.
- `account_program` and `closure_lifetime` clean under `-dPXX_HEAP_DEBUG`.
- aarch64 untouched — it has its own `EmitVariantClearA64`, and the x86-64 body
  was already x86-64-only.

### What this costs the matrix now

719 NilPy jobs x ~2.3s saved is **~1,650 CPU-seconds per full tier**, against
the ~3,016 that removing the tax entirely would give. Track T's next full tier
at `13e196cc8` gives the real figure.

### What is LEFT — the profile has changed shape, so re-read it before starting

After both fixes (44,064 samples, three runs, `-O2 -g` at `13e196cc8`), the
compiler is no longer emission-bound. The text assembler went **13.2% -> 0.6%**.

| | share of in-.text |
| --- | --- |
| builtin runtime blob (heap alloc/free + ansistr retain/release) | **35.5%** |
| parse + lex, of which `ParseFactorCore` alone is **9.4%** | ~25% |
| IR lowering (`IRLowerAST` 5.0%) | ~7% |
| symbol lookup (`UNameMatch` 2.7%, `FindUClass` 1.4%, ...) | ~5% |
| the text assembler | ~0.6% |

So the remaining 2.9s **is** genuinely "parse 24,460 lines, build the AST/IR/
symbol tables, and allocate while doing it". Three follow-ups carry it:

- **`perf-a-cache-the-compiled-nilpy-runtime-unit-image`** — the original Fix A,
  re-costed against the new numbers. Still the only route to ~0.3s, still the
  only one whose failure mode is a silently stale code buffer.
- **`perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor`** — Track P's
  file: 41,032 calls issuing 1,583,871 `CaseEqual`, i.e. **38.6 string compares
  per factor**, from a ~7,180-line linear `else if CaseEqual(name, '...')`
  chain. Same shape as the `AsmTextLine` chain the parent ticket fixed. Filed,
  not touched — `pasparser_expr.inc` is Track P's.
- **`perf-o-promote-constant-divisor-strength-reduction-to-o2`** — the general
  form of Cause 1.

Deliberate negative results, recorded so they are not re-hunted:

- **No other inline blob is worth deduplicating.** The most-repeated 24-byte
  sequence left in the output occurs 462 times and the most-repeated 40-byte one
  232 times, against `EmitVariantClear`'s 9,859. That granularity is done.
- **The ansistring release fast path is already minimal** — `test/je/dec/jne/
  ret` is ~4.3% of in-.text purely because it is called millions of times.
  Reducing it needs fewer retain/release *calls*, which is an IR-level question,
  not a blob-level one.
- **`-O3` for the compiler binary itself is worth ~12% and is not this fix.**
  A `-O3` self-build ran 4.43-4.80s against `-O2`'s 5.14-5.49s at the time,
  most of which was the same idiv now fixed at the source.

## Log
- 2026-08-26 — resolved. Code landed as 1202429f4 and 13e196cc8; this write-up as 8df2eda4c.
