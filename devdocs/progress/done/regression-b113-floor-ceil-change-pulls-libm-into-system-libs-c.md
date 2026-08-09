---
track: B
prio: 70
type: regression
blocked-by: []
---

# NEW-RED: `--system-libs=c` now links libm — the Floor/Ceil result-type change

- **Type:** regression (test-core red on master) — **Track B** (the RTL change
  that caused it), filed from a Track A session per "T owns the tool, never the
  bug; file it into the owning lane".
- **Bisected by Track T**, not by me:
  `test-core#src:test/csystem_libs_granular_libc_b113.c`, bad
  `b39ac8f02003`, last good `a3ab6ac85452`, 2 commits in range — and only one of
  those is a code change:

```
b39ac8f02 fix(rtl): Floor/Ceil return Integer like FPC's; add Floor64/Ceil64
```

## What fails

```
make test-core
  ./pascal26 --system-libs=c test/csystem_libs_granular_libc_b113.c ...
  ! readelf -d ... | grep -q "Shared library: [libm.so.6]"     <-- fails
```

The test's whole point (its header comment) is that with `--system-libs=c`,
libc symbols become real imports **while `math.h` still resolves through PXX's
bundled Pascal math path** — so the binary must NOT carry a libm DT_NEEDED. It
now carries both.

## Why the RTL change does it

The compile emits, in the same run:

```
warning: C declaration of 'floor' disagrees with the Pascal routine 'Floor' on
         the result type (float vs non-float) — binding to the C declaration
warning: C declaration of 'ceil'  disagrees ... — binding to the C declaration
```

Making `Floor`/`Ceil` return Integer is what creates the disagreement, and the
frontend's documented response to a mismatch is to bind the C declaration
instead of the Pascal routine — which is a real libm import. So the two changes
are individually reasonable and collide: the RTL is now FPC-faithful, and the
C-side math shim is keyed on the old signature.

`sqrt` in the same file is the actual libm puller only because the whole math
group falls to the C declarations once the shim is bypassed — worth confirming
which of the three symbols is on the DT_NEEDED path.

## Not caused by the Track A work in flight

Controlled three ways: the **pinned** compiler (v252, predating everything
today) links libm on this same input; T's bisect names an RTL commit; and the
warning text matches that commit's semantics exactly.

## Suggested direction

Either give the C math shim the new signatures (a `Floor64`/`Ceil64` pairing
already exists in that commit — the C `floor`/`ceil` want the float-returning
one), or make the mismatch rule prefer the Pascal routine when a float-returning
sibling exists. The first is smaller and keeps the "binding to the C
declaration" rule honest.

## FIXED 2026-08-09 (Track B — my regression, my fix)

Root cause confirmed, and it is narrower than the ticket guessed. **`sqrt` is not
involved:** the only dynamic symbols in the failing binary were `floor` and
`ceil`.

```
$ strings -a b113 | grep -xE "floor|ceil|sqrt"
ceil
floor
```

`lib/crtl` **declared** `floor`/`ceil` with no definition and let them bind to
the Pascal `Math.Floor`/`Ceil`. That worked only while those returned `Double`.
Making them FPC-faithful broke the signature match, the frontend fell back to
the C declaration exactly as documented, and that is a real libm import.

Fixed by the ticket's preferred direction — giving the C shim real bodies —
which is also the honest split: C's `floor`/`ceil` return `double` over the whole
double range, FPC's return `Integer` with a 64-bit pair alongside. Two languages,
two contracts, each now implemented where it belongs instead of one borrowing
the other's.

`(long long)` round-trips are guarded past 2^52, where they are undefined and
every double is already integral.

**Signed zero was the trap.** A first cut returned `0` for `ceil(-0.5)` where C
requires `-0.0`; `floor(-0.0)` is the same question. `trunc()`'s `(long long)`
round trip loses the sign bit, and `x < 0.0` cannot see it because `-0.0` is not
less than zero — so both now consult the sign BIT. Caught by diffing against gcc,
not by reasoning.

Verified: `libc.so.6` present and `libm.so.6` ABSENT on the exact test input;
`floor`/`ceil` byte-identical to gcc across ±2.7, ±2.0, ±0.5, ±0.0, ±1e300 and
NaN; all ten crtl math tests still pass; `tools/gate.sh lib` GREEN.

**Lesson worth keeping:** I anticipated this collision class and wrote
`test/cmath_no_pascal_hijack.c` for it — and that canary PASSED throughout,
because it asserts VALUES and the values stayed right. The regression was in
LINKAGE. A canary for "does the wrong thing get bound" has to check what got
bound, not only what it returned.
