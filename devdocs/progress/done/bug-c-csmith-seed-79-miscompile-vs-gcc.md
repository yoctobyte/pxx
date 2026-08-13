---
track: C
prio: 55
type: bug
blocked-by: []
summary: "csmith seed 79 (1588 lines, UB-free by construction) computes a different global checksum under pxx than under gcc at -O0: gcc B4981522, pxx D1BEECFE. Silent wrong value, saved with its REPRO. One hit in 250 seeds — the first since the campaign's original nine."
status: done
---

# csmith seed 79: checksum disagrees with the gcc oracle

- **Type:** bug (silent wrong value) — **Track C**, with the fix likely in
  Track A codegen once reduced
- **Found:** 2026-08-13, resuming
  [[feature-c-csmith-differential-fuzzing]] (`tools/csmith_fuzz.py --iters 250`).
  219/250 agreed, 30 skipped (gcc could not build/run them), **1 miscompile**.
  A 60-seed warm-up run just before found nothing, so this is the tail the
  campaign is for.

## Reproduce

```sh
tools/csmith_fuzz.py --seed 79
```

or by hand (the harness saved everything under `/tmp/csmith-findings/`, which is
volatile — regenerate from the seed, csmith is deterministic):

```sh
csmith --seed 79 --output t.c
gcc -O0 -w -I library_candidates/csmith/include t.c -o t_gcc && ./t_gcc
./compiler/pascal26 -I library_candidates/csmith/include t.c t_pxx && ./t_pxx
```

```
gcc: checksum = B4981522
pxx: checksum = D1BEECFE
```

## Why this is worth the reduction work

csmith output is free of undefined behaviour **by construction** and ends by
checksumming every global, so a checksum difference is a real miscompile in one
of the two compilers and it is not gcc. It is also, by the campaign's own
record, the kind of bug the human-written corpora (lua, sqlite, tcc, zlib,
c-testsuite) never reach — those are written by people who avoid dark corners.

## Next step

Reduce it. 1588 lines is not a diagnosis; `creduce`/`cvise` against the
"checksums differ" property is the standard move, and the campaign ticket
records that the previous nine all reduced to a few lines each. Then the fix
lands in whichever lane the reduction points at (IR/codegen → A, C frontend → C).

## Reduction in progress 2026-08-13 — and the interestingness test is the hard part

Two reductions were run and **both thrown away**, because the reducer found the
cheapest way to make the checksums differ: introduce **undefined behaviour**.
Recording the layers, because the obvious test is not enough and this is
reusable for the next csmith finding:

| guard | catches | does NOT catch |
| --- | --- | --- |
| `-Werror=uninitialized` at **-O0** | nothing useful — gcc's analysis needs the optimiser, so it silently never fires | uninitialised reads |
| `-Werror=uninitialized`/`maybe-uninitialized` at **-O2** | most uninitialised locals | |
| UBSan + ASan | signed overflow, OOB, bad shifts | **uninitialised reads** |
| gcc `-O0` output == gcc `-O2` output | a lot, cheaply — a UB-free program cannot notice the optimiser | UB that happens to be stable across -O |
| **valgrind** `--error-exitcode` | the uninitialised reads everything above misses | |

First run (UBSan only) reduced 1588 lines to a loop over uninitialised
`i`/`j`/`k`. Second run (plus -O0/-O2 agreement) reduced to *the same shape*
with the locals hoisted to globals-by-another-name and one still uninitialised —
gcc had not warned at -O0. Only valgrind rejects it.

### A THIRD discard, and a guard nobody would think of first

Run 3 (all the UB layers, valgrind included) reduced cleanly to **14 lines** —
valgrind-clean, UBSan-clean, `-O0` == `-O2` — and was still bogus:

```c
int g_7; int32_t *g_6 = &g_7;
*l_403 = 4578424 > g_6;          /* an INT compared with a POINTER */
```

The checksum is then a function of **where the globals land**, and pxx's image
base is not gcc's. Nothing about codegen; the reducer had simply found the
cheapest remaining way to make two numbers differ.

The guard: **gcc PIE and gcc `-no-pie` must agree.** `-no-pie` moves the whole
image, so an address-independent program answers the same under both. On the
14-line file they differ (`56772008` vs `9ADD2096` — and the no-PIE build agrees
with pxx, which is the tell); on the original csmith program both are
`B4981522`. Running the same binary twice does NOT catch it: the addresses are
stable per build.

So the interestingness test needs FOUR families of guard — uninitialised reads
(valgrind), UB (UBSan/ASan + `-O0`==`-O2`), address dependence (PIE vs no-PIE),
and only then the checksum difference. The script lives beside the repro in the
scratch tree; it is worth copying into the next reduction rather than
re-deriving, because each of these cost a full reduction run to discover.

## FIXED 2026-08-13 — a suffix RE-RUNS the constant ladder, it does not widen a rung

Run 4 (all five guards) reduced the 1588 lines to **15**, and the payload is one
line:

```c
int32_t g_7 = 2324699082;          /* as int32: -1970268214 */
int32_t *g_6 = &g_7;
*l_403 = 0x9745DC78L > *g_6;       /* gcc: 1   pxx: 0 */
```

Minimal, outside csmith — every row's expectation is gcc's:

| expression (`int32_t g = -1970268214`) | gcc | pxx before |
| --- | --- | --- |
| `0x9745DC78L  > g` | 1 | **0** |
| `0x9745DC78   > g` | 1 | 1 |
| `2537528440L  > g` | 1 | 1 |
| `0x9745DC78LL > g` | 1 | **0** |
| `0x9745DC78UL > g` | 0 | 0 |

### The cause

`0x9745DC78` is 2537528440: it overflows `int` but fits `unsigned int`, so the
UNSUFFIXED hex ladder types it `unsigned int` — correct, and `cparser.inc` did
that right. The `l/L` promotion then read that rung and widened it,
`tyUInt32 -> tyUInt64`.

But C99 6.4.4.1 says the suffix **re-runs** the ladder with a different
candidate list: for a hex constant suffixed `l/L` the candidates are
`long`, then `unsigned long`. 2537528440 fits a signed 64-bit long, so it is a
positive **long** — signedness is not inherited from the rung the unsuffixed
ladder happened to stop at.

As `unsigned long` it dragged the other operand up with it: the negative int32
converted to a huge unsigned, and `>` answered 0. Silent, and exactly the class
of bug the human-written C corpora never reach.

Fix: on the `l/L` promotion, `tyUInt32` becomes `tyInt64` — unless the literal
also carried `u`/`U`, which is what the unsigned rungs are for.

### Verified

- the 15-line reduction: gcc and pxx both `checksum = 56772008`;
- **the original 1588-line seed 79: both `checksum = B4981522`** — the root fix,
  not a reduction-shaped patch;
- `test/chex_long_suffix_literal.c` (the six rows above) wired into `make test`;
- `gate.sh quick` GREEN, self-host fixedpoint byte-identical.

Track A note: this is a C-frontend typing bug (`cparser.inc`), no IR or backend
involvement.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
