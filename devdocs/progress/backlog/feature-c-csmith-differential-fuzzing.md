---
prio: 65
---

# C differential fuzzing (csmith vs gcc) — campaign, PAUSED with the harness live

- **Type:** feature / ongoing campaign — Track C (with Track A fixes as they fall out)
- **Status:** done
  Resume by running the one command below; nothing needs rebuilding or rediscovering.
- **Origin:** step 4 of [[feature-c-corpus-expansion]] ("csmith differential fuzzing").

## Read this before you touch the ownership — the shape of this ticket is unusual

**It is a standing campaign log, not an open task.** `status: done`, parked in
`backlog/`, resumed by the one command below across six sittings now. Do not
"fix" it into `working/` and do not close it: `working/` is a live lock and this
holds no lock between sittings, and there is nothing to close because the
campaign has no end state — it has a ratio.

**It is a Track C ticket whose remaining moves fall on both sides of the
file-lane boundary, and that is not a mis-filing.** Running the harness,
triaging what it finds, and fixing cfront is C's; each bug it finds is filed
into whichever lane owns it (that is the ordinary rule, not a special case).
But axis 2 below needs a `--target` pass-through added to
`tools/csmith_fuzz.py`, which is Track T's file lane. A campaign ticket like
this does not want SPLITTING — it wants each move routed as it comes up, when
it comes up. Report which side a move falls on and let the coordinator route
it; do not re-litigate the ownership of the whole ticket from scratch. (Axis 2
was routed to T on 2026-08-19, bundled with
[[bug-t-csmith-harness-reports-slow-as-a-timeout]] so T visits the file once
rather than twice.)

## Standing note — how to read a batch's numbers

**Hit count is not severity. Dedup count is closer. Neither substitutes for
reading the bucket.** Batch B below scored 56 hits and they were ONE missing
table-row family; batch A scored 1 and it was the more serious finding. A report
line is a prompt to open the bucket, never a verdict on its own.

And **a null batch is a result, not a non-event** — report a dry run as a dry
run, with its seed count and its flag set, so the next sitting does not spend
those seeds again.

## Resume in one line

```sh
make fuzz-csmith FUZZ_ITERS=200          # or: tools/csmith_fuzz.py --iters 200
```

Prereqs are already satisfied on this box: `csmith` (apt) and the runtime headers, which
`tools/install_lib_candidates.sh csmith` vendors WITHOUT root (`apt-get download` +
`dpkg-deb -x` into `library_candidates/csmith/include`, gitignored).

## Why it works — the oracle needs no judgement

csmith generates C that is free of undefined behaviour BY CONSTRUCTION, and every program
ends by printing a checksum of all its globals. So: build the same program with gcc and
with pxx, run both, compare the checksum. A difference is a real miscompile in one of the
two — and it is not gcc. The harness also builds at several pxx `-O` levels and compares
them against each other, which catches our own optimiser without needing gcc at all.

Findings are bucketed (`MISCOMPILE_VS_GCC`, `MISCOMPILE_OPT`, `PXX_CRASH`,
`PXX_COMPILE_FAIL`, `PXX_TIMEOUT`) and DEDUPLICATED — csmith throws thousands of programs
at the same few gaps, and 500 copies of one bug is not 500 bugs. Each distinct hit is
saved with its seed and a REPRO.md.

## Scoreboard when paused

**Nine bugs found and fixed in the first sitting** (2026-07-13). Every one was SILENT, and
not one was reachable by the real-world corpora we already run (lua, sqlite, tcc, zlib,
c-testsuite) — those are *written by humans who avoid dark corners*:

| # | bug | why the corpora missed it |
| --- | --- | --- |
| b306 | signed bitfields never sign-extended (`signed f:7` = -5 read as 123) | corpora use UNSIGNED bitfields |
| — | signed bitfield FILLING its unit (`signed f:8` -7 → 249) | the storage load is always unsigned |
| — | enum bitfields must stay UNSIGNED while plain `int x:8` is SIGNED | both map to tyInt32 |
| b307 | struct-valued comma passed by value → SEGV; also on the RHS of `=` | a comma is not an lvalue |
| b308 | a discarded expression statement did not RUN (`f() ^ 3;` never called f()) | values were right, only side effects vanished |
| b309 | multidim array of POINTERS ignored its brace initializer (local AND global) | 1-D and multidim-int both worked |
| b310 | anonymous bit-fields (`unsigned : 0;`) made the whole aggregate OPAQUE — sizeof 0 | rejected outright, silently |
| b311 | multidim LOCAL array of STRUCTS initialised only its first element | nDims hard-coded to 1 |
| b312 | global pointer to a multidim array element lost its initializer → null | only one `[...]` was consumed |
| — | C99 hex float (`0x1.0p-28f`) + leading-dot (`.5f`) literals | blocked csmith from running at all |

After these, **MISCOMPILE_VS_GCC is at zero** across a 40-program sweep; the residual
failures are crashes (still one dominant class — see below).

## What is still open

- **A residual crash class.** `/tmp` findings are gone by now, but it reproduces in
  minutes: run the harness and reduce (recipe below). Last known unreduced crashers were
  csmith seeds 901 and 1502 (generated with the DEFAULT csmith flags).
- **Bitfield LAYOUT** ([[bug-c-bitfield-packing-sizeof-vs-gcc]]) — `sizeof` of a packed
  bitfield struct is 12 where gcc gives 8. Values are right, so the checksum oracle CANNOT
  see it; it breaks ABI/interop instead.
- **Brace elision over rows** ([[bug-c-multidim-brace-elision-flattens-rows]]) —
  `int q[2][3] = {{1},{2}}` gives q[0][1]=2 instead of 0. Pre-existing.
- **`--opts 0,2,3`** — the harness only ran `-O0,-O2` in anger. Adding `-O3` would point
  the same oracle at Track O's newer passes for free.
- **Cross targets.** Everything so far is x86-64. The same programs under qemu would
  exercise aarch64/arm32/i386/riscv32 codegen against the same oracle. High value, cheap:
  the harness only needs a `--target` pass-through and `tools/run_target.sh`.

## Reduction recipe (no creduce on this box — these work without it)

1. **Name the guilty variable in seconds.** csmith programs take an argv flag that prints a
   checksum after EVERY global:
   ```sh
   ./t_gcc 1 > g.txt ; ./t_pxx 1 > p.txt ; diff g.txt p.txt | head
   ```
   The first divergent line names the variable. This is how the bitfield bug went from
   2474 lines to a 6-line repro.
2. **For a crash, find the last function entered:** inject `printf("TR func_N\n"); fflush(stdout);`
   at the top of each function. Match the brace on the line AFTER the signature — csmith
   writes `{ /* block id: 0 */`, not a bare `{`. Then bisect inside that function the same way.
3. **Shrink the search space, not the program:**
   ```sh
   tools/csmith_fuzz.py --iters 30 "--csmith-args=--max-funcs 2 --max-block-depth 2 --max-expr-complexity 2"
   ```
   gives ~300-line crashers instead of 1700. NOTE the `=` — argparse eats a bare
   `--csmith-args --no-x`.
4. `sudo apt install creduce` would make all of this much faster and is worth it.

## Traps (paid for in wasted time)

- **Call ORDER differing from gcc is NOT a bug.** C leaves argument evaluation order
  unspecified; csmith only guarantees the OUTPUT is order-independent. Do not chase it.
- **Replaying a seed without the same `--csmith-args` generates a DIFFERENT program.**
  Use the saved `t.c` in the findings directory, not just the seed.
- **A `printf` you inject can move or hide the crash** — that means memory corruption, and
  it is a signal, not an annoyance.

## RESUMED 2026-07-18 — ~300 iters (seed 5000+), 2 finding buckets (both pre-existing)

Ran `tools/csmith_fuzz.py --iters 300 --seed-start 5000`. ~95% agreed with the gcc
oracle (rest skipped = gcc-side build/run fails). Two deduped finding buckets, BOTH
confirmed pre-existing (the pinned stable compiler reproduces them — not from the
2026-07-18 C multi-dim / float work):

- **MISCOMPILE_VS_GCC (seeds 5038, 5194, …) — RECURRING, SERIOUS.** pxx prints a
  wrong global checksum at -O0 (all pxx -O levels agree, differ from gcc). Filed
  [[bug-a-csmith-o0-miscompile-seed5038]] (prio 55). Multiple seeds hit the same
  bucket → a common codegen/lowering bug.
- **PXX_COMPILE_FAIL (seed 5004) — kind-5 AN_BINOP.** `IR_UNSUPPORTED: could not
  lower AST node (kind 5)`. Pre-existing: the pinned compiler fails it EARLIER at
  "wrong number of array subscripts" (the partial-multi-dim-index bug fixed
  2026-07-18 in de649c39) — so recent work fixed the first gap and exposed this
  deeper AN_BINOP-lowering one. Same kind-5 family seen in
  [[bug-c-ptr-to-array-parameter]] history.

**Blocker for fixing:** both need reduction from ~2.5k-line generators; `creduce`/
`cvise` are not installed here (apt/pip need root/PEP-668) and a homemade line-delta
reducer floors ~800 lines (csmith's nested exprs need a C-aware reducer). Install
creduce to reduce + fix. Reproducers (this box's csmith) preserved in the session
scratchpad; seeds reproduce exactly via `tools/csmith_fuzz.py --seed N`.

## 2026-07-18 — TWO miscompiles found AND FIXED via small-program fuzzing

Small-program mode (`--csmith-args "--max-funcs 1 --max-block-size 3
--max-block-depth 2 --max-expr-complexity 4 --max-array-dim 2
--max-array-len-per-dim 3 --max-pointer-depth 2"`) makes findings born ~130-160
lines → a homemade line-delta reducer (interestingness: gcc runs & pxx runs &
checksums differ) got them to 20-40 lines, directly diagnosable WITHOUT creduce.

- **seed 5038/5194/8020 → signed/unsigned 64-bit comparison** (`int64 > 0UL`
  compared signed). FIXED 574fcac1. [[project_c_signed_unsigned_compare64]].
- **seed 9048 → global pointer to struct-array element wrong stride**
  (`static T *p = &g[1]` used TypeSize(tyRecord)=8 not RecSize; `*p=..` corrupted
  the wrong slot). FIXED 4f4aceb3.

Both were pre-existing (pinned reproduced). After both fixes, all four reduced
repros match gcc. The remaining PXX_COMPILE_FAIL (seed 5004, kind-5 AN_BINOP) is
still open ([[bug-a-csmith-o0-miscompile-seed5038]] history) — a lowering gap,
lower severity (clean error).

## Post-fix verification (2026-07-18)

After both miscompile fixes: 650+ fresh iters clean — small-mode seeds 9000-9250
& 12000-12250 (243/250 agree) and higher-complexity (--max-funcs 2
--max-expr-complexity 6) seeds 20000-20200 (188/200 agree), **0 findings**, and
the harness's pxx -O-level cross-check reported no MISCOMPILE_OPT (validates the
-O3 float xmm-fusion against csmith too). The reducible-complexity miscompile
space is clean. Deeper hunting needs full-complexity csmith → ~2.5k-line repros
that require `creduce`/`cvise` (not installed; root/PEP-668) to reduce. Only the
open PXX_COMPILE_FAIL (seed 5004, kind-5 AN_BINOP) remains — didn't recur in
650+ small/mid iters, so it needs a specific full-complexity shape.

## 2026-07-18 — 3rd miscompile (seed 31039), creduce wall reached

A further small/mid-complexity batch (--max-funcs 2 --max-array-dim 3
--max-pointer-depth 3, seeds 31000+) found another pre-existing -O0 miscompile
(g_22 checksum), filed [[bug-a-csmith-o0-miscompile-seed31039]]. Unlike 5038/8020,
it does NOT reduce below ~90 lines with the homemade line-reducer (nested
functions + pointer chains + safe_math), so it is CREDUCE-GATED like 5004.
Summary: 2 miscompiles reduced-and-FIXED (signed/unsigned, struct-array-ptr
stride); 2 open findings (31039 miscompile, 5004 compile-fail) both need
`creduce`/`cvise` to reduce to a diagnosable core. NEXT: install creduce (root)
to unblock the remaining findings, or a C-aware reducer in Track T tooling.

## 2026-07-18 — seed 31039 FIXED (4de51285), not creduce-gated after all

Localized WITHOUT creduce by instrumenting the diverging global g_22 with a printf
at its mutation site (both compilers, p_3 identical) → pinpointed `(int8)g_15 >=
(uint16)g_74` compared unsigned instead of signed (C integer promotion to int).
Fixed 4de51285 (sub-int compare promotion). Now 3 miscompiles found+fixed
(574fcac1 signed/unsigned-64, 4f4aceb3 struct-array-ptr, 4de51285 sub-int-promote);
only the PXX_COMPILE_FAIL (seed 5004, kind-5 AN_BINOP) remains open.


## RESUMED 2026-08-13 — one new bug, found and fixed

First run since the 2026-07-13 pause. 60 seeds warm-up: nothing. 250 seeds:
**one** `MISCOMPILE_VS_GCC` (seed 79), reduced and fixed as
[[bug-c-csmith-seed-79-miscompile-vs-gcc]] — an integer literal's `l/L` suffix
was widening the rung the unsuffixed ladder picked instead of RE-RUNNING the
ladder, so `0x9745DC78L` was an unsigned long and `0x9745DC78L > <negative
int32>` silently answered 0.

Confirmation run after the fix: 80 seeds, **seed 79 among them, all ok, no
findings**.

Scoreboard: 390 seeds this session, 1 finding, 1 fixed. That ratio is the point
of the campaign — the previous nine came in one sitting because the low-hanging
gaps were still there; the tail is one bug per few hundred programs, and none of
them is reachable from the human-written corpora.

### The reduction guards are the real cost, and they are now written down

Three reductions were discarded before a valid one: two read uninitialised
locals (gcc's `-Wuninitialized` does not fire at `-O0`; UBSan cannot see them —
valgrind can) and one compared an int with a pointer, making the checksum depend
on where the globals land (caught by requiring gcc PIE and `-no-pie` to agree).
The five-layer interestingness test is in that ticket; copy it rather than
re-deriving it.

## SESSION 2026-08-15/16 — 550 seeds, one bug fixed, one open

Two sweeps run in the background while other tickets were worked: 250 seeds
from 90000, 300 seeds from 91000.

- **seed 90202 — fixed.** Reduced to a one-page repro and closed as
  [[bug-c-a-struct-assignment-used-as-a-value-runs-its-rhs-twice]]: `y = (x =
  f())` walked the inner `copy_rec` twice — once as a top-level statement, once
  as the outer copy's source — so `f()` ran twice. Every VALUE was right and
  only the side effects doubled, which is exactly why the whole human-written
  corpus (lua, sqlite, tcc, zlib, c-testsuite) missed it and a checksum found
  it. Pinned by `test/cstruct_assign_value_side_effects.c`.
- **seed 90044 — not a bug.** Filed as `PXX_TIMEOUT`, but both binaries
  finished and agreed; pxx took 18.2s to gcc -O0's 6.9s. The harness's fixed
  wall-clock limit sits between the two, and the bucket name sends the reader
  hunting an infinite loop. Tool fix filed as
  [[bug-t-csmith-harness-reports-slow-as-a-timeout]].
- **seed 91110 — OPEN, unreduced.** `MISCOMPILE_VS_GCC`; the divergence is in
  the elements of `g_42`. The per-global checksum trick (`./t_gcc 1` prints a
  checksum after EVERY global) is the lever — it names the first global that
  differs and cuts the reduction to that one. Start here next session.

Scoreboard for the session: 550 seeds, 2 findings, 1 fixed, 1 unreduced.
Parked to `backlog/` rather than left in `working/` — the campaign is a standing
one and `working/` is a live lock.

### seed 91110 — reduced and fixed, 2026-08-16

The open one above is closed. Reduction path, for the next reader: the
per-global checksum (`./t_gcc 1`) named `g_42[2]` and a direct print narrowed it
to one value (1 vs 0); a gdb watchpoint on `g_42[2]` named the two writes that
reach it; a printf at the second showed both operands already differing, which
moved the hunt back to the first, in `func_27` — whose struct argument was
`((*l_1698) = l_1697)`. Eleven lines out of 1723.

The bug: `ResolveNodeRec` had no AN_ASSIGN arm, so the argument resolved to
REC_NONE and the by-value record temp took the 8-byte fallback size —
[[bug-c-a-struct-assignment-passed-by-value-copies-only-eight-bytes]]. The full
1723-line program now agrees with gcc on every checksum.

Note that BOTH bugs this campaign found in two sessions are the same construct
from two angles: a struct assignment used as a value, once for how many times it
RUNS and once for what its VALUE is. That is worth reading as a hint about where
to look next — the C expression forms that hand-written code has no reason to
write are where the frontend's coverage actually thins out.

### 2026-08-16 — a CLEAN sweep, which is also data

300 seeds from 92000, run against the fix for seed 91110: **258 agreed with the
gcc oracle, 42 skipped (gcc itself could not build or run them), no findings.**

Worth recording rather than dropping, because the campaign's value is the RATIO
and a clean run is half of it. Ten findings came out of the first sitting, then
one per few hundred programs, and now zero in three hundred. That is the shape
of a tail, not of a fuzzer that stopped working — the two hits before it were
both the same construct (a struct assignment used as a value) seen from two
angles, which is what a thinning frontier looks like.

### 2026-08-16 — a second clean sweep (400 seeds), and the axis that is left

400 seeds from 94000: **354 agreed with the gcc oracle, 46 skipped, no
findings.** Seven hundred programs in a row now with nothing, against the same
default csmith flags that produced ten bugs in the first sitting and one per few
hundred after that. Read that as the default-shape space being worked out, not
as the fuzzer being finished — a fuzzer only ever finds what its generator's
flags can express.

So the next findings have to come from a NEW AXIS, and the ticket has been
listing three of them since July:

1. **`--opts 0,2,3`** — the harness has only ever run `-O0,-O2` in anger, so
   Track O's `-O3` passes have never been pointed at this oracle. Free: the
   cross-check between our own -O levels needs no gcc at all, and a
   disagreement there is a miscompile we own outright. Running now, seeds 95000+.
2. **Cross targets** under qemu — the same programs against aarch64 / arm32 /
   i386 / riscv32 codegen. Needs a `--target` pass-through and
   `tools/run_target.sh`.
3. **csmith flags the defaults leave off** — the two bugs this campaign found in
   August were both "a struct assignment used as a value", a form hand-written
   code has no reason to write. That is the tell: coverage thins where the
   GENERATOR is shy, not where the corpus is.

### 2026-08-16 — axis 1 done: `-O3` in the mix, still clean

300 seeds from 95000 with `--opts 0,2,3`: **266 agreed with the gcc oracle, 34
skipped, no findings** — and no `MISCOMPILE_OPT`, which is the part that is new.
That bucket compares our own -O levels against each other and needs no oracle at
all, so this is the first time Track O's `-O3` passes have been differentially
tested against `-O0`/`-O2` on random programs rather than on the suite.

Running total for the campaign's default-shape space: 1000 seeds since the last
finding. Axis 1 of the three is now spent; **the next findings have to come from
axis 2 (cross targets under qemu — needs a `--target` pass-through and
`tools/run_target.sh`) or axis 3 (csmith flags the defaults leave off)**, not
from more seeds at the same settings. Worth doing axis 2 next: it points the
same oracle at four backends that have never seen a random program.

## Log
- 2026-08-16 — resolved, commit e9262d5db.

## 2026-08-19 — axis 3 opened, worked and CLOSED: three flag sets, two findings, both loud

Axis 3 is "csmith flags the defaults leave off", picked on the ticket's own
principle that **coverage thins where the GENERATOR is shy, not where the corpus
is**. Three batches, 150 seeds each; A and B against a HEAD fixedpoint at
`cc20f7101`, C at `e6a14039a`. The verdict is at the end of this section.

### Batch A — `--paranoid --max-pointer-depth 4 --max-struct-fields 15 --max-union-fields 8 --max-array-dim 3`

Seeds 200000-200149. **125 agreed with the gcc oracle, 24 skipped, 1 finding, no
miscompiles.**

- **seed 200056 — `PXX_COMPILE_FAIL`, a capacity ceiling.** "string table
  overflow" on a 14125-line program with **9426 distinct string literals**
  against `MAX_STRS = 8192`. Filed
  [[bug-a-string-table-cap-refuses-a-14k-line-c-program]] (Track A — `defs.inc`
  / `emit.inc` are core, so C found it and A owns it). Measured there: raising
  the cap makes the program compile in 2.7s and agree with gcc, but
  `VisCacheVis` is *sized* by `MAX_STRS` while being *indexed* by unit, and its
  full-array clear sits on the name-lookup path — so the naive one-line raise
  buys a quiet slowdown. The ticket says fix that coupling first.
- What the flag bought: `--paranoid` emits a pointer assertion with its own
  message text at every pointer op, so literal count scales with program size
  instead of staying flat the way hand-written C's does. That is the whole
  reason this ceiling had never been hit — no corpus program is literal-dense.

### Batch B — `--builtins --builtin-function-prob 40 --max-funcs 3`

Seeds 210000-210149. **48 agreed, 46 skipped, 56 hits deduping to 11 distinct —
and all 11 were one gap**, not eleven.

Every one was `call to undeclared function: __builtin_<X>`. cfront renamed six
gcc bit builtins onto crtl helpers and was missing the rest:

- the **`l` row of families it already had** — `__builtin_clzl`, `ctzl`,
  `popcountl`. `clz`/`clzll` were both there and `clzl` was not, on all three
  families. This is the double-case shape `normalise-dont-special-case.md`
  warns about, caught by the generator rather than by a reader.
- `__builtin_ffs` / `ffsl` / `ffsll`, `__builtin_parity` / `parityl` /
  `parityll`, `__builtin_bswap16` / `32` / `64` — absent entirely.

Fixed under Track C (cfront + `lib/crtl`, both C's own files, no core change).
The `l` row resolves through `CLongWidthSuffix`, which reads `TARGET_PTR_SIZE`
— C `long` is machine-word-sized, so `__builtin_clzl` is the 64-bit helper on
LP64 and the 32-bit one on ILP32, exactly the rule `ParseCDeclType` already
applies to `long` itself. A hard-coded 64 would have been silently wrong on
i386/arm32/riscv32; verified under qemu on all four cross targets, where the
`l` rows correctly read 24/32/31 against x86-64's 56/64/63. `ffs` and `parity`
are DEFINED at zero in gcc, so they are written to answer it rather than routed
through `ctz`/`popcount`.

**All 11 seeds now compile AND agree with gcc's checksum** — the builtins are
not merely accepted, they are right on real generated programs.
`test/c_builtin_bits.c` pins the family against gcc.

### Reading batches A and B

Batch B's ratio looks alarming (56 hits in 150 seeds) and is the opposite of
alarming: it is ONE missing table row family, found instantly because the
generator was finally allowed to emit the construct. Batch A's ratio looks
clean (1 in 150) and found the more serious thing. **Hit count is not severity**
— dedup count is closer, and neither is a substitute for reading the bucket.

Neither batch produced a `MISCOMPILE_VS_GCC`. The default-shape space has now
gone 1000 seeds without one and these 300 did not change that; what axis 3
bought was a capacity ceiling and a coverage gap, both invisible to a checksum
oracle because both fail LOUDLY. Worth saying plainly: **axis 3's yield so far
is compile-fails, not miscompiles.** If the next flag set is also loud-only,
that is evidence the remaining silent bugs need axis 2 (cross targets) rather
than more generator flags.

Flag sets tried and spent, so nobody repeats them: `--paranoid` + deep
aggregates (1 finding), `--builtins` (1 finding, 11 buckets). **Not yet tried:
`--float`** — deliberately deferred, because csmith checksums floats by hashing
the bits, so any ulp difference reads as a full divergence and the bucket cannot
distinguish a codegen bug from an fp-contraction difference against gcc. That
needs `-ffp-contract=off` on the gcc side before it is worth a sweep, and the
findings would need the float-scope rules applied by hand.

### Batch C — the prediction, tested: `--inline-function --inline-function-prob 80 --max-funcs 6 --max-expr-complexity 8 --max-block-depth 4`, `--opts 0,2,3`

Seeds 220000-220149, HEAD fixedpoint at `e6a14039a`. **131 agreed with the gcc
oracle, 19 skipped, ZERO findings — no miscompile, no compile-fail, nothing.**

Run deliberately as the test of the prediction written above ("if the next flag
set is also loud-only, that is evidence the remaining silent bugs need axis 2"),
not as another sweep. The set was picked to give the SILENT buckets their best
shot: `--inline-function` at 80% drives the inliner, and `--opts 0,2,3` makes
`MISCOMPILE_OPT` live — that bucket compares our own `-O` levels against each
other and needs no gcc oracle at all, so it can catch an optimiser bug on a
program gcc refuses to build.

**Verdict on the prediction: confirmed, and more strongly than it was stated.**
The prediction expected another loud-only batch; what came back was quieter than
that — not even a compile-fail. Axis 3 (generator flags) is spent as a source of
new signal on x86-64: three flag sets, 450 seeds, two findings, both loud, and
the batch aimed squarely at silence returned nothing. 1450 seeds total on this
axis without a single `MISCOMPILE_VS_GCC`.

**So: stop here, and the priority moves to axis 2.** Track T's `--target`
pass-through is now the thing standing between this harness and the untested
surface, and it inherits axis 3's priority — running the same generator against
i386/arm32/aarch64/riscv32 tests four backends' worth of codegen that no seed
has ever reached, whereas a fourth flag set would re-test x86-64.

Flag sets tried and spent (do not repeat): `--paranoid` + deep aggregates,
`--builtins`, `--inline-function` + deep expressions with multi-`-O`. Still not
tried: `--float`, for the reason above.

## 2026-08-20 — axis 2 opened (cross targets): 370 seeds, THREE comparison classes, zero findings

Binary: self-hosted fixedpoint at **`272e347bb`** — `make compiler/pascal26`
rebuilt deliberately at that sha before the first batch (the tree had an edit on
top of the previous build), tree clean, no pin taken.

Axis 3 closed with the prediction "the remaining silent bugs need axis 2". This
is axis 2's first sitting, and the first thing it turned up was not a compiler
bug but the **shape of the axis**: on this box there is no cross gcc of any kind
(`aarch64-linux-gnu-gcc`, `arm-linux-gnueabihf-gcc`, `riscv64-linux-gnu-gcc` —
none installed; `gcc -m32` accepts the flag and then cannot link, no `Scrt1.o`).
qemu-user IS present, so we can RUN every target and cannot independently
JUDGE any of them. That splits axis 2 into three classes with different
evidentiary strength, and they must be reported separately or the numbers lie.

### D1 — aarch64 through the harness, no oracle: 150 seeds, 0 findings

`tools/csmith_fuzz.py --target aarch64 --iters 150 --seed-start 300100`.
**136 ran clean across pxx `-O` levels, 14 skipped, no findings.** The harness
said so itself, in the header: `NO ORACLE for aarch64 (LP64) --
aarch64-linux-gnu-gcc: not installed`, so `MISCOMPILE_VS_GCC` and `PXX_SLOW`
were **NOT CHECKED**. What this batch does cover is real and worth having:
`MISCOMPILE_OPT` (our own `-O` levels against each other), `PXX_CRASH`,
`PXX_COMPILE_FAIL`, `PXX_TIMEOUT` — 136 csmith programs compiled and ran on the
aarch64 backend without one of them. That is a first for this campaign; every
prior seed in 1450 hit x86-64 only.

But a batch whose strongest bucket is switched off is a weak batch, and saying
"150 seeds on aarch64, clean" without the qualifier would overstate it by
exactly the bucket that has found most of this campaign's bugs.

### D2 — the LP64 differential, oracle restored: 120 seeds, 0 findings

Then the harness's own doctrine (`tools/csmith_fuzz.py`, ~line 120: *"The data
model decides whether a checksum is comparable at all; the ISA does not"*)
answered the missing-oracle problem. aarch64 is LP64; so is native x86-64 gcc;
both little-endian. **A native gcc checksum IS comparable with an aarch64 pxx
checksum**, because a csmith checksum is arithmetic over integers of a given
width, not machine code.

Seeds 310100-310219, native `gcc -O0` vs `pascal26 --target=aarch64` run under
`tools/run_target.sh`: **105 agreed, 15 skipped, 0 divergences.**

That restores `MISCOMPILE_VS_GCC` for aarch64 with no cross toolchain
installed, and it is the batch with real teeth in this sitting.

It also surfaced a Track T defect, filed through the coordinator as
`bug-t-csmith-oracle-list-is-keyed-on-isa-when-its-own-doctrine-says-data-model`
(T, p60): `ORACLE_CC` keys its candidate compiler list on the **ISA**, so
`--target aarch64` looks only for an aarch64 gcc and reports NO ORACLE, while
the doctrine three screens above says the **data model** is what decides. The
fix is nearly free — `fuzz_one` already builds and runs a native gcc on every
seed as a validity filter and already has its checksum in `gcc_out`, so for any
LP64 target the oracle is *already computed and then discarded*.

**Trap recorded for whoever implements it: reuse the CHECKSUM, never the
TIMING.** `oracle_sec` scales pxx's time budget; feeding a native gcc's seconds
into an emulated target's budget would manufacture `PXX_TIMEOUT` findings —
`bug-t-csmith-harness-reports-slow-as-a-timeout` in costume. Comparability of
checksums is governed by the data model; comparability of timings by the
execution environment, and those are different questions. So: set `oracle_sum`,
leave `oracle_sec` `None` for emulated targets, keep timing NOT CHECKED.

### D3 — the ILP32 cross-backend class: 100 seeds, 0 findings, 0 layout-suspect

The three ILP32 backends against **each other** on the same program — i386,
arm32, riscv32, seeds 320000-320099. Not an independent oracle (both sides are
ours); a different question: not "is pxx right?" but "is pxx self-consistent?".
**84 agreed, 16 skipped, 0 layout-suspect, 0 findings.**

Two design points in this class are worth keeping, because both were nearly got
wrong:

1. **A native-gcc validity filter still belongs here**, even though its checksum
   is useless across the data-model boundary. It is answering only "is this
   program buildable and runnable at all" — without it, a csmith hiccup gets
   filed as a pxx compile failure it is not. On this run the filter is doing
   only that original job.
2. **Same data model does NOT mean same ABI.** SysV i386, AAPCS32 and the
   riscv32 psABI have genuinely different bitfield and struct-packing rules, and
   a csmith checksum reaches layout through unions and bitfields. "We own both
   sides" means any difference is *ours*; it does not mean any difference is a
   *defect* — ownership of the code is not ownership of the specification it
   implements. So a divergence here is triaged at the moment of the hit, not at
   reduction time: re-run the same seed with `--no-bitfields --no-packed-struct
   --no-unions`, and if the three then agree it is `LAYOUT-SUSPECT` (possibly a
   legitimate ABI difference) rather than a backend bug. Deliberately NOT
   disabling those constructs sweep-wide — bitfields produced 3 of this
   campaign's first 9 bugs.

The triage did not fire this sitting (0 layout-suspect), so it is untested
machinery; it is written into the script so the next hit is classified rather
than argued about.

### Reading the sitting

**370 seeds, zero findings — a dry sitting, reported as one.** That is a result,
not a non-event, but it is a weaker result than the raw number suggests and the
weighting matters: 120 of the 370 (D2) had the strongest oracle this campaign
has; 150 (D1) had no `MISCOMPILE_VS_GCC` at all; 100 (D3) had a self-consistency
check instead of an oracle. So the honest one-liner is **"120 seeds of real
cross-target differential, plus 250 of loud-bucket-only coverage, all clean"** —
and D1/D2 should be read as a PAIR, since they are the same backend with the
strongest bucket off and then on.

The backends are in better shape than the absence of a cross toolchain made it
look. What axis 2 needs next is not more seeds at this strength but the Track T
oracle fix, which converts every LP64 cross batch into a D2 automatically and
would make an i386/arm32/riscv32 differential possible against a `-m32` gcc on a
box that has one.

Scoreboard delta: seeds 1450 → 1820; findings unchanged; first non-x86-64 seeds
in the campaign's history (250 of them).

### CORRECTION 2026-08-20 — the LAYOUT-SUSPECT discriminator above is INVALID in the direction it was written for

Track T measured the D3 triage and it does not do what it says. **csmith's
option set is part of its RNG input**, so re-running a seed with
`--no-bitfields --no-packed-struct --no-unions` does not yield the same program
minus those constructs — it yields a *different program* (T measured seed 90044
going 1879 → 3373 lines with a different checksum). Agreement from that rerun
therefore carries almost no power to clear the original divergence, which was
the classifier's entire job.

The other direction survives: if the layout-free run *also* diverges, that is a
fresh finding on its own merits. But "agrees, therefore layout-dependent" was
never valid, and the D3 script must not be used to make that call again.

What replaced it in `tools/csmith_fuzz.py` (T, `174186b5d`) is better than
either of our versions: it reads csmith's own `XXX` statistics footer for the
two constructs that can actually reach a checksum — union variables, and structs
with bitfields — because **csmith hashes named FIELDS through `transparent_crc`,
not raw bytes**, so padding and alignment cannot reach the checksum at all. That
narrows the ABI caveat well below where D3 put it. A divergence in a program
with neither construct is a `MISCOMPILE_VS_GCC` with the caveat explicitly
retired; anything else is `LAYOUT_SUSPECT`, naming the construct and its count.
`LAYOUT_SUSPECT` ranks *with* the miscompiles and is deliberately kept out of
the exit code, so a red exit cannot become pressure to misfile an ABI difference
into Track A.

D3's numbers are unaffected (it recorded 0 layout-suspect, so the invalid arm
never fired) and so is the sitting's reading. What is retracted is the claim
that the triage is sound-but-untested machinery: it is unsound in one direction,
and that was not visible until someone measured what the flags do to the
generator rather than reasoning about what they mean.

Second lesson, T's, worth more than the fix: their first detector grepped the C
source for `\bunion\b` and reported unions in **12 of 12** programs — every hit
was the footer line `XXX total union variables: 0`. A true fact about the wrong
subject, inside the classifier written to prevent exactly that. **The thing you
grep for appears in the metadata too.**

## 2026-08-20 (later) — axis 2 with a REAL oracle: 160 aarch64 differential seeds, dry

Binary: self-hosted fixedpoint at `21f05c52b` (`make compiler/pascal26`,
converged in 1 round). Tool at T's `174186b5d`.

T's data-model oracle landed, and the header line is the whole difference. The
morning's D1 run said:

```
NO ORACLE for aarch64 (LP64) -- aarch64-linux-gnu-gcc: not installed.
MISCOMPILE_VS_GCC and PXX_SLOW are NOT CHECKED this run
```

and this one says:

```
vs gcc -O0 oracle (datamodel)
oracle: gcc (LP64, matches the DATA MODEL, not the ISA) -- runs natively.
Checksums are compared; TIMING is not (PXX_SLOW is off this run)
```

So aarch64 moved from the weak class to the strong one with no change on our
side. **`E:` 129/150 agreed with the gcc oracle, 21 skipped, no findings**
(seeds 330000-330149), plus a partial second batch of 31 agreed / 2 skipped
(seeds 330200-330232) before it was killed from outside this session — see
below. **160 real cross-target checksum comparisons, zero divergences.**

### Weighting, stated as before

This is 160 seeds of the STRONGEST class this campaign has: a different backend
from the one that generated the checksum, compared against an external oracle,
on a target Track O actually invests in. It is not 160 seeds of loud-bucket
coverage. Against that, the sample is small — the x86-64 axis has 1450 — and a
dry 160 bounds only what it measured: it says the aarch64 backend does not
diverge on csmith's *default* construct mix at `-O0`/`-O2`, not that it is
clean. The morning's 250 loud-bucket-only seeds are not superseded by this;
they measured a different thing (crashes, compile failures, hangs) and remain
the only coverage riscv32 has.

Scoreboard: 1820 -> 1980 seeds.

### What I checked in T's implementation before running

Three things differed from what was sketched, and all three are improvements:

- The oracle-reuse guard is `cfg.oracle_cc == VALIDITY_CC`, not a data-model
  comparison. The data-model version is **wrong** and it is worth recording why,
  because it reads as the more principled test: the validity filter always runs
  plain native `gcc`, so the moment the probe picks `gcc -m32` for an ILP32
  target, a data-model guard would say "same model, reuse it" and compare a
  32-bit target against 64-bit `long`s — the exact wrong-width comparison the
  file exists to refuse, reached by way of an optimisation.
- The LAYOUT-SUSPECT discriminator I proposed and retracted this morning is
  replaced by one reading csmith's own `XXX` statistics footer for union
  variables and bitfield-carrying structs. The fact that settles the scope:
  **csmith hashes named fields through `transparent_crc`, not raw struct
  bytes**, so ordinary padding and alignment cannot reach a checksum at all.
  The caveat is narrower than either side of this morning's exchange assumed —
  it is bitfield ALLOCATION and union PUNNING only.
- `LAYOUT_SUSPECT` ranks with the miscompiles in the report but is deliberately
  outside the exit code, so a maybe cannot fail a run.

### riscv64 is listed but unreachable

`HOST_ORACLE` carries `riscv64: LP64` and a `riscv64-linux-gnu-gcc` entry.
**pxx has no riscv64 backend** — there is no `TARGET_RISCV64` in `defs.inc`,
only riscv32. The entry is correct-in-advance, not currently live, so this
oracle fix buys exactly ONE target today: aarch64. riscv32 stays ILP32 with no
oracle on this box (`gcc -m32` accepts the flag and cannot link — no `Scrt1.o`).
Worth knowing before anyone reads "aarch64 and riscv64" as two targets' worth
of new coverage.

### Two runs killed from outside this session

The second 150-seed batch was killed twice, at seed 4 and at seed 33, both
times mid-run. Nothing in this session issued a stop; no csmith or qemu process
survived either kill; ~8 GB was available and the kernel log is not readable
unprivileged, so OOM is unruled-out rather than ruled out. The first 150-seed
batch had completed normally minutes earlier, so it is not deterministic. Noted
rather than fought — restarting into a third kill would have added nothing.
The known repo hazard here is a peer's `pkill -f <script>` matching another
agent's run of the same tool, which has happened before in this checkout.
