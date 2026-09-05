---
track: A
prio: 45
type: feature
blocked-by: []
summary: "BOTH HALVES NOW LAND AT -O3. Float half ec95c2beb (2.72x microbench, 1.18x math unit). Record half here: record-returning leaves inline via a new InlineRecResultOk predicate, a straight-line record-body validator with PER-FIELD definite assignment, and a Result temp carrying its rec id. DELIVERED 1.54x on the dd kernels on an unloaded box (min-of-7 interleaved wall clock), 1.67x under fleet load by two independent instruments; hand-inlined bound 3.0-3.3x, so the compiler captures 50-60% of the available win and the remainder is the record temp the splice still materialises. -O0/-O1/-O2/-O3 ALL byte-identical on compiler.pas -- the feature is inert on the compiler's own source, so the self-host fixedpoint proves nothing about it. The first working version SEGFAULTED at -O3 (splice returned IR_LOAD_SYM of a record where an aggregate call yields IR_LEA of its hidden destination), caught by a directed matrix, which optfuzz structurally cannot provide: pasmith returns only integer kinds (a4c89e31d). Branching record bodies, whole-record assigns and non-leaf dd kernels all still decline."
status: done
---

# Inline float-returning and record-returning leaf functions

- **Type:** feature (optimizer — **Track O**, file-owned by **Track A**:
  `compiler/**`, the inline pass). Filed by Track B, which measured it and does
  not edit the optimizer.
- Found 2026-08-15 while making `lib/rtl/math.pas`'s transcendentals fast.

## The measurement

One `sin` kernel call, the same arithmetic three ways:

| | time | accuracy |
| --- | --- | --- |
| double-double Taylor over the dd primitives | 7.96 us | correctly rounded |
| **identical arithmetic, hand-inlined by me** | **2.11 us** | correctly rounded, **bit-identical** |
| plain-double minimax kernel | 0.029 us | ~1 ulp |

Row 2 is the one that matters here. Nothing about the computation changed — same
operations, same order, same output bits — only the calls went away. **3.8x, for
free, from a transform the compiler already performs on integer code.**

The dd kernels are the extreme case (a `DdMul` is ~10 float ops behind a call,
and a Horner loop makes 26 of them), but the shape is everywhere: small leaf
functions returning `Double` or a two-field record are exactly what numeric
library code is made of.

## Scope correction (measured later the same day) — read before ranking this

The 3.8x above does **not** generalize. Measured on the plain-double fast `Sin`
path, hand-inlining every call into one function bought only **1.2x** (77 ms ->
65 ms per 1M). The dd kernels are an outlier precisely because the callee is so
small that the call dominates it.

The 7.2x on that same workload is the **value model**, not calls:
[[feature-opt-float-register-temporaries]], which carries a Double as raw bits
in RAX and so emits three GPR<->XMM transfers plus a stack round-trip per
operation — 316 `movq` in one function where gcc emits zero.

So: this ticket is real and cheap, but it is the ~20% and that one is the 7x.
Rank accordingly, and do not let this one be mistaken for the fix.

## What the inliner does today

It accepts int/ordinal-returning leaves and rejects anything returning a float
or a record. Worth checking whether that is a deliberate ABI-return-slot
restriction or just where the implementation stopped — the by-value float return
path and the record return path both work correctly for ordinary calls, so the
values themselves are not the obstacle.

## Suggested scope

Leaf functions only, no branches or one branch, returning `Double`/`Single` or a
record of two such fields — which covers `DdMul`, `Dd2Sum`, `DdFast2Sum`,
`DdAdd`, `DdMulD`, `DdBits` and their peers, i.e. the whole hot set. That is a
much smaller change than general float inlining and captures most of the 3.8x.

Per Track O's rule, land behind `-O3` and promote to `-O2` per-pass after the
full gate.

## Gate

`make test` + self-host byte-identical (the compiler is itself full of small
leaf functions, so the fixedpoint is a real test of this), plus
`test/lib_math_correctly_rounded.pas` under `-dPXX_FLOAT_EXACT` producing the
**same bits** at `-O2` and `-O3` — inlining must not change a result, and this
test is the sharpest available detector of that.

## Triage 2026-08-19 (Track D re-triage pass) — confirmed at the instruction level

Not just still open: **measured in the emitted code**, which is stronger than
the timing the ticket was filed on. Two identical leaves, one `Double`, one
`Integer`, compiled `-O3 -S` against the v363 pin:

```pascal
function AddD(a, b: Double): Double;   begin AddD := a + b; end;
function AddI(a, b: Integer): Integer; begin AddI := a + b; end;
```

The disassembly contains `call AddD` and **no** `call AddI` — the integer leaf
is inlined at -O3 and the float leaf is not, from the same source shape. That
is exactly the asymmetry the ticket describes, isolated to two lines.

**Genuine feature, still wanted**, and the cheapest possible repro is now on
record for whoever takes it.


## 2026-09-04 (frank-optimize) — the float half landed at -O3; the RECORD half is untouched and holds the headline

**The ticket's open question is answered, by measurement rather than by reading.**
"Deliberate ABI-return-slot restriction, or just where the implementation
stopped?" — it stopped. The whole restriction was one four-line predicate,
`InlineScalarTk` in `compiler/inline_expand.inc`, whose accepted set ends at
`tyPointer` (17) with the floats sitting at 18/19/20 immediately after it.
Widening it self-hosts on the first try.

### What landed

- `InlineScalarTk` accepts `tySingle`/`tyDouble` **when `OptLevel >= 3`**, per the
  Track O charter. `tyExtended` deliberately stays out: 10-byte x87 with its own
  load/store path, not an SSE2 register scalar.
- An `AN_FLOAT_LIT` arm in `InlineExprSimple`, same `-O3` gate. Without it the
  change was nearly pointless — `Sq := x * x` inlined while `Mix := a * 0.5 + b * 0.25`
  declined, and coefficients are what numeric kernels are *made of*.
- The stale doc comment above `InlineExprSimple` ("Rejects ... managed/float")
  corrected in the same commit.

### A miscompile this opened, found and fixed here

Admitting floats opened the **float arm of the dropped-narrowing bug fixed in
191af3440**. Shape 1 retains the RHS and drops the assignment, and the store is
where the narrowing lives. The existing guard tests `TypeIsOrdinal` on BOTH
sides, so it could not see it. Measured at -O3, all correct at -O0/-O2 and
correct out-of-line:

| | -O3 before the guard | correct |
| --- | --- | --- |
| `D2S(1/3)` into a Double | 0.33333333333333331 | 0.33333334326744080 |
| `I2S(16777217)` | 16777217 | 16777216 |

Fixed by routing **any** RHS whose kind is not already the float result kind to
shape 3, which stores through a properly typed Result temp — one condition, not
a second predicate that distinguishes narrowing from widening
(`normalise-dont-special-case`). `NarrowD` still inlines afterwards, via shape 3
rather than shape 1, so the guard costs correctness nothing and value nothing.

### Promise — delivered value, measured, control vs mine, min-of-N interleaved

Control `1968c7a7da57` (stock HEAD, confirmed byte-identical to the `make`-built
binary) against the change. Two distinct sha256s, printed.

| workload | control | mine | |
| --- | --- | --- | --- |
| float-leaf microbench, 20M iters | 0.49 s | 0.18 s | **2.72x** |
| math unit (`Sqrt`+`Sin`+`Ln`), 10M iters | 3.65 s | 3.10 s | **1.18x** |

The second is the honest one. On that program the change removes **8 of 206
calls** (7x `Abs`, 1x `FastSinK`); `Sin`/`Sqrt`/`Ln` themselves are retained but
decline at the call site, which is not yet explained and is the obvious next
thread.

### THE HEADLINE 3.8x IS THE RECORD HALF, AND IT IS NOT IMPLEMENTED

`DdMul`, `DdAdd`, `DdAddD`, `DdMulD`, `Dd2Sum`, `Dd2Prod`, `DdFast2Sum`,
`DdDiv`, `DdDivD`, `DdSqrt` all return **`TDd = record Hi, Lo: Double end`**.
Only `DdBits` returns a plain `Double`. So the sin-kernel measurement this
ticket was filed on belongs entirely to the record half, and **nothing in this
commit moves it.** Do not read the 1.18x as a refutation of the 3.8x, and do not
read the 3.8x as delivered. They are different halves of the same ticket.

### Safety, and a gap in the net that is worth its own ticket

- `-O0`/`-O1`/`-O2` **byte-identical** on `compiler/compiler.pas` (~4150 procs),
  control vs mine, same source tree both sides.
- Self-host fixedpoint: `converged after 1 round(s)` on every build.
- The ticket's own named gate, `test/lib_math_correctly_rounded.pas` under
  `-dPXX_FLOAT_EXACT`, agrees -O0/-O2/-O3 — but its whole output is one line
  (`MATHROUND OK`), so it is a much weaker detector than "same bits" suggests.
  Its value here is that the probe shows float routines really are retained in
  that compile, so it is at least reaching the new code.
- **`tools/optfuzz.sh` cannot see this feature at all.** `pasmith.py` has no
  float generation — zero `Double`/`Single` declarations across five seeds at
  optfuzz's own flags, and no `--floats` knob exists; its 28 "float" hits are
  prose and one `argparse type=float`. So the harness that exists *specifically*
  because curated gates missed 21 silent -O3 inliner divergences is structurally
  blind to float inlining. Running it here proves the **integer** path is
  unregressed and nothing about the new surface. Filed separately.

### Proof — stated as blocked, not as passed

Track O's PROOF gate is Track T's full tier. Not attainable right now: the
sweeping host cannot produce `skip_holes == 0` (no RDRAND, open `decide-`), and
has produced 308 full-tier reports with zero GREEN. So this is **promise
measured, proof outstanding**, and it stays at `-O3` — which is where the
charter puts an unproven pass anyway. No promotion is requested.

### The regression test, and its positive control

`test/test_inline_float_result_narrows.pas`, wired at **-O0 and -O3** (an -O2-only
arm cannot catch this, because floats are not admitted below -O3). It is the
float sibling of `test_inline_result_narrows` and mirrors its structure,
including the four rows that must NOT change — widening and same-kind cases that
still take shape 1, so a future guard cannot pass by disabling float inlining
altogether.

**Proven to fail on the broken binary**, which is the part that makes it a test:
compiled with the pre-guard compiler `df2318a5f745` it prints
`0.33333333333333331` and `16777217.0` on the first four rows and the correct
values on the last four; with `c6d5ab1a3edb` all eight are correct at both -O0
and -O3.

### A separate float differential, run but not landed as a test

14 shapes (Single/Double leaves, a Horner chain, every conversion direction, a
ternary, a multi-statement body with a float local, a global read, a non-leaf
wrapper, argument evaluation order, a Boolean-returning float comparison, and
recursion) agree across -O0/-O1/-O2/-O3 and match the stock compiler's -O3
output exactly. 12 of the 13 routines verifiably inline at -O3; `Recur` stays a
real call, which is the recursion guard behaving. Kept in the session scratchpad
rather than landed, because `test_inline_float_result_narrows` covers the arm
that actually broke and the rest duplicates `test_inline_expand`'s job.


## 2026-09-05 (frank-optimize) — the RECORD half lands at -O3. Delivered 1.55x, not the 3.8x

### What it required, and what the ticket got wrong about its own scope

The ticket's suggested scope says "leaf functions only ... which covers DdMul,
Dd2Sum, DdFast2Sum, DdAdd, DdMulD, DdBits". **Three of those six are not
leaves**: `DdMul`, `DdAdd` and `DdMulD` call the other kernels, so a leaf-only
slice cannot reach them. What it does reach is `DdFast2Sum`, `Dd2Sum`,
`Dd2Prod` (and `DdBits`, which returns a plain Double and was already covered by
the float half). Those are the innermost and most-called, which is why the win
is real anyway — they inline INTO the mid-level kernels.

### The change

- **`InlineRecResultOk`** — a record result is admitted at -O3 when it is a user
  record of at most `MAX_INLINE_REC_FIELDS` (4) fields, each a non-array,
  non-nested, inline-scalar field. **Deliberately NOT a widening of
  `InlineScalarTk`**, which also governs params and locals: widening that would
  admit record params and record locals in the same stroke, neither of which the
  splice has been shown to carry. One axis at a time.
- **`TryRetainInlineRecBody`** — straight-line `Result.Field := E` / `local := E`
  chains, with **per-field** definite assignment (`RetResFieldDef`). A single
  Boolean cannot express it: `Result.Lo := b - (Result.Hi - a)` reads a field the
  previous statement wrote, which is the shape of every dd kernel. Every field
  must be definite at the end, or the caller's temp carries stack garbage in the
  fields nobody wrote — silently, because the other fields look right.
- **Straight-line only.** A record inside an `AN_IF` would need
  `InlineIfValidate`'s save/merge to carry a per-field vector rather than one
  Boolean. The kernels this axis exists for are all straight-line; branching
  record bodies decline.
- **The Result temp carries its rec id**, set through `LastTypeRecId` the way
  `IRBuildHiddenDest` does it, not by writing `SymTR` afterwards.

### The bug this shipped with first, and why the directed matrix existed before the code

The first working version **SEGFAULTED at -O3 while -O0 and -O2 were correct**.
`IRInlineExpand` returned `IR_LOAD_SYM` of a record symbol; an aggregate call
returns `IR_LEA` of its hidden destination, so the caller was handed sixteen
bytes of record where it expected a pointer. Fixed by matching the real call's
shape.

**optfuzz could not have found this.** `pasmith` returns only integer kinds from
every function it generates — no record returns at all — so the designated net
for splice-machinery changes is blind to this entire axis
([[bug-t-pasmith-returns-only-integer-kinds-so-optfuzz-is-blind-to-the-return-type-axis]],
sharpened today from "no float code" to the wider true statement). The matrix in
`test/test_inline_record_result.pas` was written BEFORE the feature, as a
pre-change control, and it is what caught the crash.

Two further defects of my own, both found by measuring rather than reading:
`UFldArrLen` is an element COUNT and reads 1 for a plain scalar field, so testing
it against 0 rejected every record; and the read-before-write guard recursed
through the field node into the bare Result ident and demanded `InlineResultDef`,
a whole-Result flag a field-wise body never sets, so every kernel that reads back
a field it just wrote declined after the node-class guard had accepted it.

### PROMISE — delivered, and it is well under the hand-inlined bound

Control `9f65e23ccbdc` (stock, same tree) vs `9ac545b62722`, `-O3`, min-of-7
interleaved, seven pxx/make processes on the box by the process table (NOT by
load average, which lags and was reading ~2x the real contention):

| | | |
| --- | --- | --- |
| dd kernels, out-of-line (today) | 0.310 s | 1.00x |
| **dd kernels, this change** | **0.200 s** | **1.55x** |
| same arithmetic hand-inlined | 0.090 s | 3.44x |

**Report 1.55x.** The hand-inlined 3.44x reproduces this ticket's recorded 3.8x
and is the PRIZE, not the delivery: hand-inlining also lets the arithmetic fold
and CSE across the merged body and writes straight to the destination, while the
splice still materialises a record temp and copies it. **The remaining ~2.2x is
that temp**, and eliminating it — splicing directly into the caller's
destination when the call result is immediately assigned — is the obvious next
piece and is not in this change.

### Safety

- `-O0`/`-O1`/`-O2` **byte-identical** on `compiler/compiler.pas` (~4250 procs),
  control vs change, same source both sides.
- Self-host fixedpoint converged on every build.
- `tools/gate.sh quick` **GREEN**, verdict read from that run's own
  `logs=/tmp/pxx-gate-<pid>` line and watched to completion. An earlier attempt
  was KILLED after 14 passing checks; it produced no `gate: GREEN` line and was
  discarded rather than reported, because a partial run is not a verdict.
- `test/test_inline_record_result.pas` wired at **-O0 and -O3** (an -O2 arm
  cannot catch this — records are not admitted below -O3), carrying three rows
  that must NOT inline (`Trunc` call, whole-record assign, branching) so a future
  guard cannot pass by declining everything.

### PROOF — outstanding, and no promotion is requested

Track T's full tier is the proof gate and it is stale by 85 testable commits
with seven dist-upgrading, so **no cross-target verdict exists for this tree**.
Native green does not cover i386/arm32/riscv32/aarch64. This stays at `-O3`,
which is where the charter puts an unproven pass. Promotion, when T returns, is
one pass at a time.

## 2026-09-05 — re-measured after the revert and pin v404

The first record-half numbers (1.55x) were taken on a tree that `2d6bfadd6`
(frankB's assignment-type-check revert) has since moved. Re-took **both** arms
rather than re-baselining one against the old control, which is the cheapest way
to turn a real number into a plausible wrong one. Both arms rebuilt from the
same base, `converged after 1 round(s)` each time.

| | control | change | ratio |
| --- | --- | --- | --- |
| unloaded box, wall clock, min-of-7 | 0.3264s | 0.2114s | **1.543x** |
| under fleet load (~16-19), wall clock, min-of-7 | 0.4740s | 0.2846s | 1.665x |
| under fleet load, **user CPU**, min-of-9 | 0.30s | 0.18s | 1.666x |

The revert did not touch this: 1.55x before, 1.543x after, same conditions.

**The published number is 1.54x — the conservative one.** The ratio is
load-sensitive in a direction that makes sense (the call-heavy control loses more
to contention than the inlined arm does), so the busy-box 1.67x is not the claim
even though two independent instruments agree on it.

Hand-inlined bound, same tree, bit-identical output: 0.0994s unloaded / 0.10s
user-CPU → **3.0-3.3x**, so **50-60% of the available win is captured**. The
remainder is the record temp the splice still materialises; eliminating it means
splicing directly into the caller's destination and is not attempted here.

### Two null instruments, banked

**`objdump -d` does not disassemble a pxx-emitted ELF** — 3 lines of output
total. So `objdump -d bin | grep -c 'call.*Dd2Prod'` returns **0**, and 0 is
exactly what successful inlining looks like. It returns 0 for a nonexistent file
too, so one number spans *inlined*, *not inlined*, and *never built*. It was in
the earlier evidence and was worthless. Caught only because a build failed and
both arms still read 0.

The aimed instrument is `PXXDBG=a.inline`: the change arm retains
`DdFast2Sum shape=4` and `Dd2Prod shape=4`, the control retains neither (0 vs 2).

**A process-table count filtered to `pascal26|pxx|make|fpc` is not a load
check.** It read 0 while a qemu-system-xtensa at 180% and a python at 63% were
on the box. "No pxx processes" and "quiet box" are different claims; use
`/proc/loadavg` for the second.

### What is NOT proven

`gate.sh quick` GREEN (logdir `/tmp/pxx-gate-1543221`, verdict read from that
run's own first line), including the FPC seed canary — which only runs while
`compiler/**` is dirty, so it was gated before the commit, not after. The
`pinned builds live lib/rtl` row is the multi-fixture sampler here (22s;
`b6212f43f` is an ancestor now), so the caveat carried on the float half no
longer applies.

optfuzz: 205 programs, 0 diffs, 0 o0-compile-skips — **integer path only**, by
construction. It cannot reach a record return.

**No promotion requested.** PROOF is Track T's full tier; there is no full tier
at this tree and pin v404 was itself graded `reds`. Both halves stay at `-O3` as
measured promise.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1f94f6a03.
