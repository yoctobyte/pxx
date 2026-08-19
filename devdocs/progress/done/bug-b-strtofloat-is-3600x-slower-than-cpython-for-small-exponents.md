---
track: B
prio: 30
type: bug
blocked-by: []
summary: "REMAINING WORK IS SUBNORMALS ONLY, and it is no longer Eisel-Lemire. Three passes have landed: no-double-parse + no-quadratic-append (4.7x on the fast path), and now Eisel-Lemire, which took every NORMAL value outside Clinger's window from 18-526 us to under 1 us (27x-1100x, 592,994 values diffed against CPython, 0 mismatches). The two rows this ticket named 'small' and 'subnormal' are BOTH subnormal and did not move: Lemire declines below the normal floor by construction, as Go and Rust do. They sit at ~535 us vs CPython's 0.72 us. The fix for them is a rewrite of ExDecNearest to compare in BINARY big-integer arithmetic instead of expanding each candidate to its exact ~765-digit decimal. The title's 3600x, its 63-step cause and its 'small exponents' boundary have each been measured wrong and corrected in the body — read the notes, not the title."
status: done
owner: frankonpiler-etree
---

# `StrToFloat` is milliseconds per value for small exponents

- **Type:** bug (performance) — **Track B** (`lib/rtl/sysutils.pas`).
- Found 2026-08-15 while timing the differential harness for
  [[bug-b-sqrt-is-1-ulp-low-on-some-normal-inputs]]: a 121,000-value sweep took
  about a minute, and isolating it showed **none** of that was the `Sqrt` under
  test. It was reading the inputs.

## Measured

5000 values per row, one `StrToFloat` each, versus CPython's `float()` on the
identical strings:

| input class | pxx | CPython | ratio |
| --- | --- | --- | --- |
| mid-range (`1..1000`) | 116 us | 0.28 us | ~410x |
| small (`~1e-310`) | 2.9 ms | 0.72 us | ~4000x |
| subnormal (`~1e-320`) | 2.6 ms | — | — |

Isolated with a parse-only program (read line, `StrToFloat`, accumulate) so no
formatting, no arithmetic and no I/O of the result is in the number. Sqrt vs
SqrtSoft timings were identical to two decimals across every class, which is
what pointed at the parser rather than the callee.

## Why it is slow, and why that is not a defect in the answer

The fast path is Clinger's: significand under 2^53 and |exponent| <= 22, one
multiply, exact. Everything else falls to `ExDecNearest`, which is a 63-step
ordered search over the IEEE bit pattern where **each step expands a candidate
double to its exact decimal expansion** and compares. For an exponent near the
denormal floor that expansion runs to ~1080 digits, so the cost is 63 x
big-decimal — milliseconds.

That design was chosen deliberately and its header says why: there is no
estimate that can be wrong by an unknown number of ULP, so the result is
correctly rounded by construction. **Do not trade that away.** The bug is that
the fast path is narrow, not that the slow path is careful.

## The fix

Widen the fast path; keep the exact search as the fallback it was meant to be.

- **Eisel-Lemire** (what CPython, Rust, Go and Abseil use) answers ~99.9% of
  real inputs with a 128-bit multiply against a power-of-ten table, and — the
  part that matters here — it *knows when it cannot decide* and defers. So it
  composes with the existing search rather than replacing it: fast path,
  Lemire, then `ExDecNearest` for the handful Lemire declines.
- Cheaper interim, if the table is unwelcome: extend the exact-multiply path
  past |expo| <= 22 using a two-step exact power (10^22 x 10^k) for the range
  where the significand stays under 2^53. Worth much less than Lemire but is
  perhaps twenty lines.

## Where it bites

Any program reading a column of scientific-notation numbers: a CSV of sensor
readings, a `.obj`/mesh file, a JSON document of floats, and every differential
test harness in this repo that feeds values on stdin. At 2.9 ms a value, a
100k-row file costs five minutes in the parser alone.

## Gate

The mid-range and small-exponent rows above drop by at least an order of
magnitude; `test/lib_floattostr.pas` and the round-trip tests stay green
byte-for-byte (correct rounding is not negotiable here); a randomised
round-trip sweep — `FloatToStrExact(x, 17)` then `StrToFloat` — returns exactly
`x` across the whole exponent range including subnormals; `make lib-test` green.

## 2026-08-17 (frank3) — the stated cause is WRONG; a 2.2-3.1x fix landed; the gate is NOT met

Measured against `pinned` **v344**, `-O2`. Reproduced the ticket's numbers first
(95.6 us mid / 2657 us small / 2584 us sub), so the symptom is exactly as filed.

### The diagnosis in this ticket is wrong, and it changes the fix

> *"a 63-step bit-pattern search"*

**It is about 4 steps, not 63.** Instrumented `ExDecNearest`'s `CmpBits` with a
counter:

| class | `ExDecNearest` calls | `CmpBits` calls | per parse | longest expansion |
| --- | --- | --- | --- | --- |
| mid | 322 | 1336 | **4.1** | 53 digits |
| small | 400 | 1600 | **4.0** | 765 digits |
| subnormal | 400 | 1600 | **4.0** | 765 digits |

The search is seeded from `ExDecEstimate` and the doubling bracket converges
almost immediately — the 63-step figure would be the *unseeded* worst case, and
the seed is doing its job. So the cost is **not the number of comparisons, it is
the price of one**, and the "widen the fast path so fewer inputs reach the
search" framing is aimed at the wrong term: 4 comparisons at ~650 us each is
what 2.6 ms is made of.

### What the price of one comparison actually was

Each comparison expands a candidate double to its exact decimal via
`ExDecOfMant`, which built its digit string as:

```pascal
ds := IntToStr(buf[n - 1]);
for i := n - 2 downto 0 do
begin
  lp := IntToStr(buf[i]);
  while Length(lp) < 9 do lp := '0' + lp;   { and this, per limb }
  ds := ds + lp;                            { reallocates + recopies everything }
end;
```

That is **quadratic**: every limb reallocates and recopies the whole accumulated
prefix, and a subnormal is ~765 digits over 85 limbs. Replaced with a string
sized once and filled by index.

| class | before | after | speedup |
| --- | --- | --- | --- |
| mid-range | 95.6 us | **30.5 us** | 3.1x |
| small (~1e-310) | 2657 us | **1192 us** | 2.2x |
| subnormal (~1e-320) | 2584 us | **1166 us** | 2.2x |

The residue is the big-decimal multiply itself — for a subnormal, `exp2` is
about -1074, so ~82 rounds of `ExDecMul(buf, n, 5^13)` over a limb array growing
to ~85, i.e. ~14k 64-bit divisions per expansion, times four expansions. That is
inherent to expanding-to-exact-decimal and will not come down by tuning; it
comes down by **not doing it**, which is what Eisel-Lemire buys.

### Correctness — the part that was not negotiable

- **Round-trip sweep, 218,883 values, 0 mismatches**: every binary exponent x 8
  mantissas, the 2000 smallest subnormals one by one, 300 powers of two each
  way, the named boundaries, and 200k random finite bit patterns.
  `FloatToStrExact(x, 17)` then `StrToFloat` returns the identical bit pattern.
- **Formatter output byte-identical to before the change**: 155,884 lines
  (`FloatToStrExact` at every precision 1..17 plus `FloatToStr`, over every
  exponent and the subnormal floor) diffed against a build of the pre-change
  `sysutils.pas`. `cmp` clean. `ExDecOfMant` feeds both directions, so this was
  the check that mattered.
- `make lib-test` green.

### Landed as a gated test, because nothing guarded this

`test/lib_strtofloat_roundtrip.pas` (~2.7 s, in `make lib-test`). `lib_floattostr`
checks the FORMATTER against expected strings; the exact PARSE path had **no
test at all**, which is how a performance change here could have traded away
correct rounding silently.

It immediately earned its place by flagging `-0.0`. That turned out to be **FPC
parity, not a bug**: measured against FPC 3.2.2, `FloatToStr(-0.0)` prints `0`
there too, while `StrToFloat('-0')` returns negative zero — the formatter drops
a sign the parser preserves. pxx agrees on both halves bit for bit. (CPython
differs, `repr(-0.0)` is `-0.0`, but FPC is this RTL's oracle.) The asymmetry is
now asserted explicitly so a future one-sided "fix" breaks the test.

### This ticket's gate is NOT met — deliberately left open

> *"The mid-range and small-exponent rows above drop by at least an order of
> magnitude"*

3.1x and 2.2x are not 10x. **Eisel-Lemire remains the fix** and is now correctly
scoped by the measurement above: it wins by removing the exact expansion from
the common path entirely, not by reducing a step count that was never 63. The
quadratic string build was a real and independent defect sitting underneath it,
worth landing on its own — it also speeds up `FloatToStr` for every long
expansion — but it is not the ticket.

Moved back to `backlog/` so it can be ranked: it is not parked waiting on
anything, it is remaining work.

## 2026-08-18 (frank3-fc) — the title names the wrong axis, and the biggest cost was TWO PARSES

**Compiler binary: `pinned` v352, sha `0d2087d629bf`, pin commit `b14da0847`,
`-O2`.** Every A/B below is the same compiler with only `lib/rtl/sysutils.pas`
differing, so nothing here is a pin artefact.

### Where the cliff actually is — measured against the INTERNAL exponent

The title says "small exponents". It is not small exponents, and it is not one
cliff. The parser's fast path tests `nd <= 15` and `-22 <= expo <= 22`, where
`expo` is the exponent **after** the decimal point is folded in
(`expo := e - fracCount`). Sweeping that directly, 2000 values a row:

| nd | expo | before |
| --- | --- | --- |
| 15 | 0 … 22 | ~2.5 us (flat) |
| 15 | **23** | **41.9 us** — a 17x step at the edge |
| 15 | 100 / −100 | 161 us / 248 us |
| 15 | 200 / −200 | 187 us / 605 us |
| 15 | −300 | 1109 us |
| **17** | **0** | **22.1 us** — no exponent at all, and already 9x the fast path |
| 17 | −300 | 1138 us |

So there are three separate facts the one title flattens:

1. **The edge is `|expo| > 22` in EITHER direction**, not "small".
2. **A 16- or 17-digit significand alone falls off it**, at exponent zero —
   which is every value a differential harness writes with
   `FloatToStrExact(x, 17)`, i.e. the exact case that found this ticket.
3. Past the edge the cost **grows with `|expo|`** (the expansion gets longer),
   and the negative side is 2-3x the positive at equal magnitude.

The earlier note in this ticket already corrected the *stated cause* (4 search
steps, not 63). This corrects the *stated boundary*.

### The largest single cost was not float work at all

`StrToFloat` → `TryStrToFloat` → **`StrToFloatDef` twice**, once defaulting to
`0.0` and once to `1.0`, comparing the two answers because the parser had no
way to report failure. Every `StrToFloat` therefore parsed its input **twice**,
including two full `ExDecNearest` searches on the slow path.

Measured before believing the source — `StrToFloat` against `StrToFloatDef` on
identical input:

| shape | StrToFloatDef | StrToFloat | ratio |
| --- | --- | --- | --- |
| nd=15 expo=0 | 1501 ns | 2287 ns | 1.52x |
| nd=15 expo=23 | 20383 ns | 40301 ns | **1.97x** |
| nd=15 expo=−100 | 125814 ns | 244726 ns | **1.94x** |
| nd=17 expo=−300 | 614140 ns | 1158790 ns | **1.88x** |

A 2x on the whole family, produced by using the default value as a failure
sentinel. Nothing about floats, and invisible from the float-parsing code.

### And the quadratic append had a sibling

`devdocs/dev/normalise-dont-special-case.md` says to grep for the sibling
before closing a double case. The 2026-08-17 note in this ticket fixed a
quadratic string build in `ExDecOfMant`; the **same shape** was sitting in the
scan loop of the parser itself — `ds := ds + c` per digit, reallocating and
recopying the accumulated prefix on every digit. Fast-path cost was linear in
digit count for that reason alone: 607 ns at 1 digit rising ~130 ns per digit
to 2565 ns at 15.

### What landed

- **One parse.** `ParseFloatCore(s, value): Boolean` is now the single parser;
  `StrToFloatDef`, `TryStrToFloat` and `StrToFloat` are wrappers. Failure is a
  returned flag.
- **No per-digit reallocation.** The digit buffer doubles (`DsPush`), so an
  ordinary number costs one allocation instead of fifteen.

### Results — same compiler, only sysutils.pas differing

| row | before | after | gain |
| --- | --- | --- | --- |
| fast path (nd=15, \|expo\|<=22) | 2823 ns | **597 ns** | **4.7x** |
| mid-range, 17 digits (the ticket's own row) | 47.8 us | **23.5 us** | **2.03x** |
| small (~1e-310) | 1205 us | **600 us** | **2.01x** |
| subnormal (~1e-320) | 1205 us | **587 us** | **2.05x** |
| `StrToFloat` / `StrToFloatDef` | 1.9-2.0x | **1.00-1.09x** | double parse gone |

Against CPython on identical strings, the fast path goes from **21x slower to
4.4x** (597 ns vs 137 ns). Cumulatively since this ticket was filed, its own
three rows are **4.1x, 4.4x and 4.3x** faster.

### Correctness

- `test/lib_strtofloat_roundtrip.pas` green — 6846 checked values, the sweep
  that exists precisely so a performance change here cannot trade away correct
  rounding silently.
- `test/lib_floattostr.pas` green.
- `make lib-test` green.

### The gate is still NOT met, and the remaining work is unchanged

> "The mid-range and small-exponent rows above drop by at least an order of
> magnitude"

2x is not 10x. **Eisel-Lemire remains the fix**, and it is now better scoped:
the residual cost is entirely the exact decimal expansion in `ExDecNearest`,
which Lemire removes from the common path rather than speeds up. One useful
datum for whoever takes it — the primitive it needs exists: `MulHiU64` in
`lib/rtl/wideint.pas`, an unsigned 64x64→128 high-half multiply, intrinsic on
64-bit targets (`IR_MULHI`) with a Pascal fallback on 32-bit. So the 128-bit
multiply is not an obstacle; the work is the power-of-ten table and the
decline-and-defer logic.

Left in `working/` → returned to `backlog/`: not blocked, just unfinished.


## 2026-08-19 (frank3-b) — Eisel-Lemire landed. 27x-1100x in the normal range;
## the two SUBNORMAL rows are unchanged, by construction, and the gate is still open

**Compiler binary: `stable_linux_amd64/default/pinned` v352, `-O2`, repo HEAD
`5a900c598`.** Every A/B below is that same compiler with only
`lib/rtl/sysutils.pas` differing, so nothing here is a pin artefact.

### What landed

`EiselLemire` in `lib/rtl/sysutils.pas`, between the Clinger fast path and
`ExDecNearest`, over a generated 696-entry table of 128-bit truncated powers of
ten (q = -348..347, Go's range). `MulHiU64` from `lib/rtl/wideint.pas` supplies
the 128x64 high half, exactly as the previous note predicted — it was not an
obstacle.

The composition is what makes it safe: Lemire **declines** rather than guesses,
so `ExDecNearest` is untouched and still answers every case Lemire will not.
Nothing about the correct-by-construction path changed.

### Results — ns per parse, same harness, before/after

| shape | before | after | gain |
| --- | --- | --- | --- |
| nd=15 expo=0 (Clinger fast path) | 635 | 680 | **0.93x — 5% SLOWER** |
| nd=15 expo=22 | 2037 | 687 | 3.0x |
| nd=15 expo=23 (the edge) | 17925 | 662 | **27x** |
| nd=15 expo=100 | 76800 | 650 | 118x |
| nd=15 expo=-100 | 115500 | 650 | 178x |
| nd=15 expo=200 | 87050 | 700 | 124x |
| nd=15 expo=-200 | 272625 | 750 | 364x |
| nd=15 expo=-300 | 526000 | 500 | **1052x** |
| nd=17 expo=0 | 9650 | 1562 | 6.2x |
| nd=17 expo=-300 | 515250 | 750 | 687x |
| nd=19 expo=0 | 9875 | 750 | 13x |
| value ~1e-296 (NORMAL) | 559000 | 500 | **1118x** |
| value ~1e-310 (**subnormal**) | 549000 | 547750 | **1.00x** |
| value ~1e-320 (**subnormal**) | 539750 | 535250 | **1.01x** |
| value ~1e-323 (**subnormal**) | 535750 | 528500 | **1.01x** |

The `expo=22` row moving at all is not a mistake: with random 15-digit
significands about 10% of values end in a zero, which the parser strips into the
exponent and pushes to 23 — so that row was always ~10% slow-path, and
0.1x17925 + 0.9x572 = 2307 predicts the 2037 measured.

### The title names the wrong axis for the THIRD time — and this one is load-bearing

Earlier notes corrected the stated *cause* ("63 steps" was 4) and the stated
*boundary* ("small exponents" was `|expo| > 22` either way, or `nd > 15`). The
remaining mis-framing is in the ticket's own measured rows: **"small (~1e-310)"
and "subnormal (~1e-320)" are BOTH subnormal**, and Eisel-Lemire declines every
subnormal by construction. So those two rows could never have been fixed by the
fix this ticket asks for.

That is easy to get wrong in the other direction too, and I did: the first cut
of the benchmark built an nd-digit *significand* and appended `e-310`, giving a
value near **1e-296** — normal, not subnormal — while labelling it subnormal.
It is the row that improved 1118x. The corrected row needs `e-324`. Anyone
re-measuring this should check with CPython which side of
`sys.float_info.min` (2.2250738585072014e-308) the row actually lands on before
believing its label.

### Correctness — the part that was not negotiable

- **592,994 values diffed against CPython's `float()`, 0 mismatches.** Random
  1-19 digit significands across q = -350..350; the normal/subnormal boundary;
  20-45 digit significands (past the u64 cap, where Lemire must not be reached);
  halfway `...5` shapes; overflow to infinity and underflow to zero from both
  sides; and the named boundaries including `2.2250738585072011e-308`, the
  decimal that famously hung PHP's parser.
- **The oracle was proved able to FAIL before its zero was believed.** Flipping
  one bit in every one of the 696 table high words produces 191 mismatches.
  (A single perturbed *low* word produces none — that word only participates in
  the rare refinement branch, which is itself worth knowing.)
- `test/lib_strtofloat_roundtrip.pas` green, 6846 values.
- `make lib-test` **green** (exit 0, against stable v352).

### Landed as a gated test, because the round-trip sweep cannot see this

`test/lib_strtofloat_lemire.pas` + `test/lib_strtofloat_lemire_check.py`, in
`make lib-test` (~2.8 s, 73,195 values, python3-optional like the mimic_codecs
oracle diff). The existing round-trip test only ever feeds the parser 17-digit
spellings of real doubles; those are not the strings that break a float parser.
A single wrong digit in a generated 696-entry table is invisible to any
self-consistent check — the parser would just return a plausible neighbour —
so the guard has to be a second correctly-rounded implementation.

### How often Lemire actually answers

| input | Clinger | reaches Lemire | accepted | declined |
| --- | --- | --- | --- | --- |
| exponents -30..30 (realistic) | 58.6% | 41.4% | **99.75%** | 0.25% |
| exponents -350..350 (adversarial) | 5.2% | 94.8% | 87.4% | 12.6% |

The declines in the adversarial row are almost entirely the subnormal and
overflow tails, which a uniform draw over the whole exponent range
over-represents enormously.

### What it costs, stated because every binary pays it

+42 KB of code, +11 KB of bss, +22 us of startup, in **every** binary that
links `sysutils` — including ones that never parse a float. Only ~11 KB is the
table's own bytes; the other ~31 KB is
[[bug-a-a-typed-const-array-is-built-by-startup-code-not-stored-as-data]],
filed from here: the compiler emits a typed const array as fill-it-at-startup
code (~29 bytes per element) rather than as initialised data. Re-encoding the
table as a string blob dodges that completely (measured: +13 bytes of code
instead of +20 KB) and was **deliberately not done** — it would hide the
compiler bug and make the table unauditable. When that bug is fixed this unit
gets ~31 KB smaller with no edit to it.

The 5% fast-path regression is code layout, not added work: adding the same
local to the OLD parser without the table changed nothing measurable. Measured
interleaved, 8 samples each, because three noisy samples had suggested 10%.

### The gate is STILL not met — subnormals — and the remaining work is a
### different fix from the one this ticket has been asking for

> "The mid-range and small-exponent rows above drop by at least an order of
> magnitude"

Cumulatively since filing: mid-range 116 us → ~0.6 us (**~190x**, met);
every NORMAL small-exponent value → under 1 us (met, by a wide margin);
but **small (2.9 ms → 548 us) and subnormal (2.6 ms → 535 us) are ~5x, not 10x**,
and did not move at all in this pass.

**Eisel-Lemire is now done and is not the answer to those rows.** Nor is
"extend Lemire to subnormals": below the normal floor the truncated 128-bit
product no longer carries enough bits to settle the rounding, which is exactly
why Go and Rust decline there too. Guessing there is the one change that would
make this parser fast and subtly wrong.

The real remaining fix is in **`ExDecNearest` itself**, and it is tractable:
its cost is that every comparison expands a candidate double to its EXACT
DECIMAL (~765 digits for a subnormal, ~82 rounds of big-decimal multiply). The
standard approach compares in **binary** big-integer arithmetic instead
(AlgorithmM / Simple Decimal Conversion, what CPython's dtoa does — and CPython
parses 1e-320 in 0.72 us, so this is a known-achievable target, not a limit).
That is a rewrite of the exact path, independent of everything landed here.

Scoped that way, it is worth its own ticket rather than a fourth pass on this
one. Returned to `backlog/`: not blocked, just unfinished — same as the two
passes before it.

## 2026-08-19 (frank3-etree) — the subnormals: 47x-70x, and THE GATE IS MET

**Compiler binary: `stable_linux_amd64/default/pinned` v355 (`739dfeb2d0e8` at
`264489d47360`), `-O2`.** Every A/B below is that same compiler with only
`lib/rtl/sysutils.pas` differing, so nothing here is a pin artefact.

### What landed — the fix the previous pass scoped, done

`ExBinNearest` in `lib/rtl/sysutils.pas`, between Eisel-Lemire and
`ExDecNearest`. Same question, same correct-by-construction guarantee, compared
in **binary big integers** instead of by expanding each candidate to its exact
decimal.

The comparison `m * 2^k ? d * 10^expo` becomes, with `10^expo = 2^expo * 5^expo`
and every negative power moved to the other side:

```
    m * 5^ta * 2^(SB+ta)   ?   int(ds) * 5^tb * 2^(SA+tb)
```

so **every power of two is a shift and only the power of five is a multiply** —
and `d` and `expo` are fixed for the whole search while only the candidate's `m`
and `k` move, so `5^|expo|` is built ONCE per parse instead of once per
comparison. The 2-power common factor is then cancelled from both sides, which
cuts a subnormal's operands by about a third (its `k` is -1074, so that shift
alone is 1074 bits).

It **declines** rather than guesses, exactly as `EiselLemire` does: every
capacity check returns False and falls through to `ExDecNearest`, which is
untouched, has no size limit, and still answers everything. Measured on the
gated test: `ExBinNearest` answers 43,528 values and `ExDecNearest` still
answers 800, so the fallback is live rather than dead code.

### Results — ns per parse, same harness, auto-scaled to >=300 ms per row

| shape | before | after | gain |
| --- | --- | --- | --- |
| fast nd=15 expo=0 (Clinger) | 614 | 631 | 0.97x |
| nd=15 expo=23 | 738 | 708 | 1.04x |
| nd=17 expo=0 | 736 | 708 | 1.04x |
| nd=15 expo=-100 | 764 | 721 | 1.06x |
| nd=15 expo=-300 | 756 | 726 | 1.04x |
| normal ~1e-296 (Lemire) | 796 | 753 | 1.06x |
| **SUBNORMAL ~1e-310** | 586000 | **11203** | **52x** |
| **SUBNORMAL ~1e-320** | 577000 | **8187** | **70x** |
| **SUBNORMAL ~1e-323** | 384000 | **6125** | **63x** |
| **SUBNORMAL min (4.94e-324)** | 378000 | **6031** | **63x** |
| nd=25 expo=-330 | 287000 | **5593** | **51x** |
| nd=40 expo=-340 | 293500 | **6203** | **47x** |

Nothing on the fast, Lemire or Clinger paths moved — this sits strictly behind
Lemire's decline, and the +/-5% either way on those rows is the same code-layout
noise the previous pass measured.

### THE GATE IS MET, for the first time in five passes

> "The mid-range and small-exponent rows above drop by at least an order of
> magnitude"

Cumulatively, against the rows this ticket was filed with:

| this ticket's own row | filed | now | cumulative |
| --- | --- | --- | --- |
| mid-range (`1..1000`) | 116 us | ~0.63 us | **~184x** |
| small (`~1e-310`) | 2.9 ms | 11.2 us | **259x** |
| subnormal (`~1e-320`) | 2.6 ms | 8.2 us | **317x** |

All three are well past an order of magnitude. The two rows that had never moved
in four passes are the two that moved most here.

### A number in this ticket that does not reproduce — CPython is not 0.72 us

The previous note set the target from "CPython parses 1e-320 in 0.72 us". On this
box, `timeit` over 200,000 calls to `float()` on the identical strings:

| shape | CPython | pxx now | ratio |
| --- | --- | --- | --- |
| fast nd=15 expo=0 | 218 ns | 631 | 2.9x slower |
| nd=17 expo=0 | 486 ns | 708 | 1.5x slower |
| normal ~1e-296 | 1573 ns | 753 | **2.1x FASTER** |
| SUBNORMAL ~1e-310 | 2607 ns | 11203 | 4.3x slower |
| SUBNORMAL ~1e-320 | 1673 ns | 8187 | 4.9x slower |
| SUBNORMAL min | 1062 ns | 6031 | 5.7x slower |
| nd=40 expo=-340 | 2141 ns | 6203 | 2.9x slower |

(timeit's lambda adds ~60 ns, negligible at these magnitudes.) So the standing
gap on subnormals is **3-6x, not 15x**, and on normal values past Clinger's
window pxx is now the faster of the two. The 0.72 us figure is not reproducible
here and should not be quoted again without a fresh measurement — the fourth
number in this ticket's history to need that correction.

### Correctness — the part that is not negotiable

- **125,609 values diffed against CPython's `float()` ad hoc, 0 mismatches** —
  40k across the subnormal band, 40k with 20-79 digit significands over
  q = -400..360, 5k with **100-600 digit** significands, 20k subnormal halfway
  shapes, 20k at the normal/subnormal boundary, and 600 with exponents out to
  +/-1,000,000 that must decline to `ExDecNearest`.
- **9,078 EXACT MIDPOINTS diffed, 0 mismatches** — generated from CPython's
  `Fraction`, covering subnormals, both boundaries, powers of two and random
  normals.
- **The oracle was proved able to FAIL before its zero was believed.** Four
  perturbations of the new code:

  | perturbation | ad-hoc sweep | gated test |
  | --- | --- | --- |
  | `5^13` constant off by one | 57,733 mismatches | 23,272 |
  | midpoint `2*mant+1` -> `2*mant` | 50,638 | 21,183 |
  | tie rule `= 0` -> `= 1` | **0 — a coverage GAP** | 60 (after the fix below) |
  | drop the 2-power cancellation | 0 | 0 |

  The third row is why the tie corpus exists: **random decimals essentially
  never land exactly halfway between two doubles**, so inverting round-to-even
  changed nothing in a 125,609-value sweep. That is exactly the shape this
  repo pays most for, and it was found by trying to break the code rather than
  by reading it.

  The fourth row passing is the intended result, not a gap: the 2-power
  cancellation is a pure size optimisation, and a perturbation that is supposed
  to be semantically neutral proving neutral is the check working.
- `test/lib_strtofloat_roundtrip.pas` green — and **2.7 s -> 0.20 s**, because
  its own subnormal sweep was paying the old cost.
- `test/lib_floattostr.pas` green. `ExDecOfMant` and the whole formatter side are
  untouched by this change; only the decimal->double direction has a second
  implementation.
- `make lib-test` **green** (exit 0) against stable v355.

### The gated test got STRONGER, because the coverage it skipped is now affordable

`test/lib_strtofloat_lemire.pas` said, in as many words, that its
boundary and long-significand blocks were held at 1500 values each *because each
one cost ~500 us*. That reason is gone, so the coverage is taken:

| block | was | now |
| --- | --- | --- |
| normal/subnormal boundary | 1500 | **20000** |
| significands past a u64 (20-45 digits) | 1500 | **20000** |
| significands of 100-600 digits | — | **2000** (new) |
| exact midpoints | — | **12** (new) |
| total values | 73,195 | **112,207** |
| runtime | ~2.8 s | **1.8 s** |

More coverage, less time. The twelve midpoints are stated per line with which
neighbour is even, and they alternate, so a rule that always rounded one way
fails half of them; they are generated from CPython's `Fraction` while the
checker derives the expected bits independently, so a wrong constant fails
loudly rather than quietly agreeing with itself.

### What it costs

**+11.8 KB of code, +0 data, +0 bss, no startup cost.** Contrast the previous
pass's Eisel-Lemire: +42 KB, +11 KB bss and +22 us of startup in every binary
that links `sysutils`, because it carries a 696-entry table. There is no table
here — the powers of five are computed per parse, on the path that already costs
microseconds — so the footprint is code only.

### The next lever, measured rather than guessed

The remaining cost is **~8 ns per 32-bit limb operation**, and everything follows
from that:

- setup (`5^ta` for ta~326, ~25 multiplies over a growing 24-limb array) is
  2.5-3.5 us of the 11.2 us, measured by returning early from `ExBinNearest`
  after the setup;
- the search itself is **6 comparisons** for a subnormal (counted, not
  estimated — same instrumentation that corrected "63 steps" to 4 two passes
  ago), at ~1.3 us each over ~26-limb operands.

So it is neither the step count nor the operand size that is left — it is the
per-limb cost, and the lever is **64-bit limbs via `MulHiU64`** (already in
`lib/rtl/wideint.pas`, intrinsic on 64-bit via `IR_MULHI`, and already used by
Eisel-Lemire here). That halves the limb count AND collapses `BigFMulU64`'s five
passes into one, and it raises the power-of-five chunk from 5^13 to 5^27. Rough
expectation ~4x, which would put subnormals at 2-3 us and inside CPython's range.
Ruled out as a smaller lever first, by measurement: shrinking the limb array from
224 to 64 changed the subnormal row by only 13%, so neither the buffer nor its
copies dominate.

That is a self-contained rewrite of the six `BigF*` primitives with no change to
the algorithm above them, and this ticket's gate is now met, so it belongs in its
own ticket rather than a sixth pass here.

**Resolved.** The gate this ticket has carried since 2026-08-15 is met on every
row it names.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
