---
slug: feature-n-mimic-zlib-gives-nilpy-cpythons-decompress-over-the-rtl-inflater
title: "mimic_zlib: CPython's zlib.decompress from Nil Python, over the RTL inflater we already have"
track: N
prio: 50
type: feature
blocked-by: [bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-mimic-shim]
status: done
created: 2026-09-10
found: 2026-09-10
found-by: frank-user, from neo-dd's question; the owner directed the shape
owner: ""
summary: "RESOLVED 2026-09-14 (frankb-56), by the route this ticket's own two self-corrections prescribed: there is no mimic_zlib, the surface lives on lib/rtl/zlib.pas beside its Pascal one, and the consumer wanted compress rather than decompress. RE-MEASURED 2026-09-14 against the three rows this ticket recorded as failing at 49489e5ca437 -- from a bare `import zlib', zlib.crc32(b\"hello\") answers 907060870 (CPython agrees), zlib.decompress(zlib.compress(b\"hello\")) answers b'hello', and the binary carries NO DT_NEEDED, so it reached lib/rtl/zlib.pas and not zlib.h. THE compress CAVEAT THIS TICKET STATES THREE TIMES IS RETIRED AND THAT IS THE PART A READER MUST NOT CARRY FORWARD: `a compress that claims a ratio is a lie' was true of DeflateZlibStored and stopped being true on 2026-09-13. DeflateZlib is LZ77 with a hash-chain match finder plus fixed AND dynamic Huffman, level selects work rather than being accepted and dropped, and png.pas builds its IDAT through the same encoder. Measured both directions, which a round trip alone cannot claim: we inflate CPython's level-9 stream correctly (1128 raw -> 332), and CPython inflates ours correctly (330 bytes, two better than CPython on that input). A byte diff against CPython still differs BY DESIGN and is not a defect to file. THE blocked-by EDGE NEVER GATED THIS: it was correct for the ticket as filed, because a mimic_zlib.pas would never be consulted while lib/rtl/zlib.pas wins the ordinary lookup -- and once the ticket corrected itself to 'put the surface in zlib.pas', the unit winning the lookup IS the unit carrying the surface. The edge stays recorded because that shim-precedence bug is real and open; it simply never blocked this. STILL TRUE AND UNCHANGED: the value was the PATTERN, not the PNG (neo-dd: tiles are SQLite, the importer has PIL, neither runtime decodes anything) -- and what the pattern bought showed up the same day, when base64.pas was found returning str where CPython returns bytes and test/lib_pysurface_repr.py was wired into make lib-test to diff the repr of every bytes-returning lib/rtl python surface against CPython."
---

# mimic_zlib

## Why it exists

neo-dd (lekkerzeilen) asked whether a PNG decoder could be written once in plain
Python over `zlib` and run on both CPython and PXX, making our native `png` unit
an optional fast path rather than a second implementation to keep in step. That
is the right instinct and it needs one thing from us: `zlib.decompress`.

The owner's ruling on the shape, 2026-09-10: *"notice that if lekkerzeilen has a
missing library feature, we should craft a shim."*

## What is already in the tree

`lib/rtl/zlib.pas` is a complete inflater — `InflateZlib` (RFC 1950),
`InflateGzip` (RFC 1952, with the CRC32 + ISIZE trailer verified), and
`InflateRawBytes` (bare RFC 1951). `lib/rtl/png.pas` has a whole decoder on top
of it. None of it is reachable from Python. This is a wrapper, not an
implementation.

## Why Pascal and not a `.py` shim

Measured, through the quoted import that does bind:

```python
import 'zlib.pas' as z
ok = z.InflateZlib(src, dst, err)     # no overload matches, for every src NilPy can build
```

`InflateZlib` takes `hashing.pas`'s `TByteArray = array of Byte`. NilPy `bytes`,
`bytearray`, `list(...)` and the return-lifted form were each tried and each
refused. A Python-side wrapper has nothing to pass.

`mimic_struct.pas` made exactly this call for exactly this reason and wrote the
reasoning down; follow it. (Its neighbours `mimic_bisect` and `mimic_copy` are
real Python, because they can be.)

Watch the type: `sysutils.pas` declares a **different** `TByteArray =
array[0..32767] of Byte` and flags the clash in its own comment. `zlib.pas`
takes `hashing`'s.

## Surface

| name | notes |
| --- | --- |
| `decompress(data) -> bytes` | the requirement. Over `InflateZlib`. Raise `zlib.error` on a refusal, carrying `PngLastError`-style text from the `err` out-parameter |
| `crc32(data, value=0) -> int` | the PNG chunk check wants it and `hashing.pas` has it |
| `decompressobj()` | **only if a caller needs it.** A PNG `IDAT` stream is concatenated chunks, which `decompress` over the joined bytes handles; do not build a streaming object on spec |
| `compress(data, level=-1)` | `DeflateZlibStored` produces valid zlib with **no compression**. Round-trips, ratio is 1.0. Ship it saying that, or leave it out — do not let a caller infer a ratio |

## The oracle is free

`tools/pydiff.py` against CPython. Decompress a stream CPython compressed and
compare bytes; that is a real differential, not a shape assertion. A round-trip
test alone would pass with a broken inflater paired to a broken deflater.

## Read before starting

[[bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-mimic-shim]]
is not paperwork — while it stands, this file is never consulted, because
`lib/rtl/zlib.pas` satisfies the ordinary lookup first. Writing it under a
different name to dodge that would put a shim in the tree under a name nothing
imports.

## RESOLVED 2026-09-14 (frankb-56, Track B) — by the route this ticket's own correction prescribed

The ticket corrected itself twice on the SHAPE and was right both times: there
is no `mimic_zlib` to write, the work is a Python surface on `lib/rtl/zlib.pas`
itself, and the consumer wanted `compress` rather than `decompress`. All of it
is in the tree and none of it needed the blocker to move.

### Re-measured 2026-09-14, against the three rows this ticket recorded as failing

The ticket's last measurement (at `49489e5ca437`) read: *"zlib.uncompress is OK,
zlib.InflateZlib still says `no member`, zlib.crc32(b"hello") still `no
overload`"*. Today, from a bare `import zlib`:

| | |
| --- | --- |
| `zlib.crc32(b"hello")` | `907060870` — CPython gives the same |
| `zlib.decompress(zlib.compress(b"hello"))` | `b'hello'` |
| `DT_NEEDED` on the binary | **none** — it reached `lib/rtl/zlib.pas`, not `zlib.h` |

### The `compress` caveat this ticket insisted on is retired, and that matters

Three separate passages here say some version of *"a `compress` that claims a
ratio is a lie; ship the first and say so, or omit it"*, because
`DeflateZlibStored` emitted valid zlib at ratio 1.0. **That stopped being true
on 2026-09-13.** `DeflateZlib` is LZ77 with a hash-chain match finder plus fixed
and dynamic Huffman, `level` selects work rather than being accepted and
dropped, and `png.pas` builds its IDAT through the same encoder — which is
exactly what the old note predicted would happen when someone wrote one.

Measured against CPython, both directions, which is the claim a round trip
alone cannot make:

    CPython's level-9 stream, 1128 raw -> 332      we inflate it correctly
    our stream of the same input, 330 bytes       CPython inflates it correctly

So `compress` compresses, and on that input beats CPython by two bytes. A byte
diff against CPython still differs by design and is still not a defect to file:
which matches an encoder finds is latitude.

### The blocker was never load-bearing for THIS ticket

`blocked-by: bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-mimic-shim`
was correct for the ticket as originally filed — a `mimic_zlib.pas` would indeed
never be consulted, because `lib/rtl/zlib.pas` satisfies the ordinary lookup
first. Once the ticket corrected itself to "put the surface in `zlib.pas`", that
edge stopped describing anything: the unit winning the lookup IS the unit
carrying the surface. The edge stays recorded because that shim-precedence bug
is real and open; it simply never gated this.

### Unchanged and still true: the PATTERN was the value, not the PNG

The ticket's own ranking note said lekkerzeilen's first use is moot — tiles are
SQLite, the importer has PIL, neither runtime decodes anything. That still
holds. What the pattern bought is visible in what it unblocked the same day:
`base64.pas` was found returning `str` where CPython returns `bytes`, and
`test/lib_pysurface_repr.py` now diffs the repr of every bytes-returning
lib/rtl Python surface against CPython in `make lib-test`.

## Log
- 2026-09-14 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6b45b991b.
