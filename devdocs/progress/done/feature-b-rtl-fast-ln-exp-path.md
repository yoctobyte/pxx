---
track: B
prio: 60
type: feature
blocked-by: []
summary: "Sin/Cos/Tan got a fast default path (261 ms vs 31,828 ms per 1M, ~1 ulp) under the 2026-08-15 float policy. Ln and Exp did not, and they are the WORSE case: 16,480 ms per 1M against glibc's 13 ms, a 1270x ratio. Same treatment — a plain-double minimax kernel by default, the existing double-double one behind -dPXX_FLOAT_EXACT."
status: done
---

# `Ln` / `Exp`: the fast default path, which trig now has and they do not

- **Type:** feature — **Track B** (`lib/rtl/math.pas`).
- Follows [[bug-b-rtl-math-transcendentals-lose-argument-reduction]] and the
  policy in `devdocs/dev/float-policy.md` (user decision, 2026-08-15: fast by
  default, exact behind a flag, a last-bit divergence is not a bug).

## Why this one is the bigger half

Measured on this box, per 1M calls, `-O2`:

| | pxx (double-double) | glibc | ratio |
| --- | --- | --- | --- |
| `Sin` + `Cos` | 29,383 ms → **261 ms** (done) | ~660 ms | was 44x |
| `Ln` + `Exp` | 16,480 ms | 13 ms | **1270x** |

Trig was the *smaller* disproportion and it is the one that got fixed, simply
because it was the ticket in hand. `Ln`/`Exp` sit under `Power`, `Log10`,
`Log2`, `**` in NilPy, and every `x**y` in user code, so the 1270x is paid far
more often than the 44x was.

## The work

Mirror exactly what `Sin`/`Cos` now do — the shape is already in the file and
worth copying rather than reinventing:

1. `FastLn` / `FastExp`: plain-double minimax kernels (fdlibm's `__ieee754_log`
   and `__ieee754_exp` are the reference; their coefficients are freely
   distributable and the existing kernels already cite them).
2. Keep the reduction exact — `Ln` splits off the exponent, `Exp` reduces by
   `k*ln2` in two chunks. That half is *not* what costs the time and it is what
   keeps the answer right at the extremes. The trig path proved the split: the
   reduction is shared between modes, only the kernel differs.
3. `{$ifdef PXX_FLOAT_EXACT}` dispatch in `Ln` and `Exp`, same as `Sin`.
4. Follow `Power`, `Log10`, `Log2` and the hyperbolics through — they call
   `Ln`/`Exp` and inherit whichever path is selected, but check none of them
   reaches into the dd kernels directly.

## Do not lose

- Special values stay EXACT in both modes: `Ln(0)` is `-Inf`, `Ln(-1)` is NaN,
  `Exp(-Inf)` is `+0`, `Exp(710)` overflows to `+Inf`, `Exp(-746)` underflows
  through the denormals rather than snapping to zero.
- The `Log10` rows in `test/lib_math_correctly_rounded.pas` where **glibc is the
  wrong one** (verified against 60-digit arithmetic) are exact-mode rows and stay
  exact-mode rows.

## Gate

`test/lib_math_fast_tolerance.pas` gains `Ln`/`Exp`/`Power` rows at a stated ulp
tolerance and stays green; `test/lib_math_correctly_rounded.pas` stays green
under `-dPXX_FLOAT_EXACT`; `tools/gate.sh lib`. **And cross-build the test for
i386 / aarch64 / arm32 / riscv32 under qemu** — the lib gate is x86-64 only, and
the trig path shipped an i386 segfault that only a qemu run caught
([[bug-a-i386-var-float-parameter-faults-on-first-access]]).

---

## DONE 2026-08-15 (landed 80bc5aa81, same day as filing)

Per 1M calls: `Ln` 9,453 -> **103 ms** (92x), `Exp` 9,085 -> **121 ms** (75x),
`Log10` 9,569 -> **144 ms** (66x), `Log2` 10,345 -> **140 ms** (74x), and `Sinh`
18,133 -> **170 ms** (107x) for free, since it sits on `Exp`.

fdlibm minimax kernels, dd path kept behind `-dPXX_FLOAT_EXACT`. Accuracy over
14,551 sampled arguments: `Ln` 90.5% bit-exact worst 1 ulp, `Exp` 89.6% worst
1 ulp, `Log2` 86.7% worst 1 ulp, `Log10` 85.2% worst 2 ulp.

Both exactness properties this ticket asked to preserve came out EXACT rather
than to tolerance, because the reductions extract the exponent by bit
manipulation: `Log10(10^n)` is exactly n for n = 0..22 and `Log2(2^n)` is
exactly n for n = -60..60. Asserted at tolerance 0.

**`Power` and `LogN` were deliberately NOT converted** and are split out as
[[feature-b-rtl-fast-power-needs-a-hi-lo-log]]. `Power` amplifies the log's
error by |y|; `LogN` is a genuine quotient with no exponent trick, and the naive
version gave `LogN(10,1000) = 2.9999999999999996`, which
`test/lib_log_exactness.pas` caught in the lib gate.

Special values verified exact in both modes and cross-checked under qemu on
i386, aarch64 and arm32 — which is how the i386 `var Double` segfault
([[bug-a-i386-var-float-parameter-faults-on-first-access]]) was caught before it
shipped.

## Log
- 2026-08-15 — resolved, commit 61a527625.
