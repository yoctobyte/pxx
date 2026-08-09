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
