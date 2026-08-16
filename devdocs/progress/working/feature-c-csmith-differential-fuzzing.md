---
prio: 60
owner: claude-acpn
---

# C differential fuzzing (csmith vs gcc) — campaign, PAUSED with the harness live

- **Type:** feature / ongoing campaign — Track C (with Track A fixes as they fall out)
- **Status:** working
  Resume by running the one command below; nothing needs rebuilding or rediscovering.
- **Origin:** step 4 of [[feature-c-corpus-expansion]] ("csmith differential fuzzing").

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
