---
prio: 35  # Track O — SIMD win for complex arithmetic, isolated (a type + a few lowerings)
type: feature
---

# Complex as a packed-double XMM value (SSE2/SSE3)

- **Type:** feature (optimization — **Track O**; file-ownership **Track A**:
  a type lowering + x86-64 codegen). x86-64 first. Isolated — not a
  compiler-wide change.
- **Opened:** 2026-07-18 (design discussion, off the XMM/SIMD thread).

## Idea

A `complex double` is (re, im) = 2×f64 = **exactly one XMM register** (re in lane
0, im in lane 1). Lower complex arithmetic to packed-double SIMD instead of two
scalar doubles + shuffling:

- **`+` / `-`:** `addpd` / `subpd` — ONE instruction does both re and im.
- **`*`:** `(a+bi)(c+di) = (ac-bd) + (ad+bc)i` — the SSE3 recipe (~5 insns):
  ```
  movddup  t1, x          ; (a,a)
  shufpd   t2, x, ...      ; (b,b)
  mulpd    t1, y           ; (ac, ad)
  shufpd   y2, y, 1        ; (d,c)
  mulpd    t2, y2          ; (bd, bc)
  addsubpd t1, t2          ; (ac-bd, ad+bc)   <- the sign flip, free (SSE3)
  ```
  With FMA: `vfmaddsubpd` collapses it further.
- **abs / conj / scale:** conj = `xorpd` a sign mask on the im lane; scale =
  `mulpd` by a broadcast; |z|^2 = `mulpd` then `haddpd`.

## Baseline caveat (ties to the CPU-feature-level question)

`addsubpd`/`movddup` are **SSE3 = x86-64-v2**, NOT the guaranteed v1 baseline
(SSE2). v2 is ~universal (every x86-64 CPU since ~2005), so requiring it is
usually fine — but for strict-v1 portability, emulate the sign flip on SSE2:
`mulpd` the cross terms, `xorpd` a `{0.0, -0.0}` mask onto one lane, `addpd`
(one extra op vs `addsubpd`). Decide per the arch policy
([[feature-opt-arch-level-and-dispatch]] if raised): plain packed add/sub is v1;
complex-mul is v1-with-emulation or v2-native.

## Storage / residency note

A complex resident is the ONE case that needs the **full 16-byte** save
(`movaps`/`movups`), not the 8-byte scalar `movsd` — both lanes are live. Feeds
into [[feature-opt-pxx-internal-abi-unified-residency]] (a complex value = one
16-byte xmm resident; align its frame slot to 16 for `movaps`).

## Scope

- A `Complex`/`ComplexDouble` value kind carried in one XMM; lower `+ - *`
  (and conj/abs) to the packed forms; scalar fallback for other targets and for
  `Extended`-based complex.
- Pascal already has a complex type in a unit — wiring the packed representation
  behind it is the natural surface.

## Acceptance

- Complex `+ - *` emit packed-double sequences on x86-64; results bit-match the
  scalar path (same IEEE double arithmetic, just fewer instructions); a
  complex-heavy bench (small FFT / Mandelbrot-in-complex) is faster.
- Gate: `make test` + self-host byte-identical (behind -O3 or a complex-type
  opt-in) + cross (scalar fallback stays correct).
