---
slug: feature-n-mimic-zlib-gives-nilpy-cpythons-decompress-over-the-rtl-inflater
title: "mimic_zlib: CPython's zlib.decompress from Nil Python, over the RTL inflater we already have"
track: N
prio: 50
type: feature
blocked-by: [bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-mimic-shim]
status: new
created: 2026-09-10
found: 2026-09-10
found-by: frank-user, from neo-dd's question; the owner directed the shape
owner: ""
summary: "THE SHAPE OF THIS TICKET IS WRONG AND THE SLUG IS STALE -- corrected 2026-09-10, same evening it was filed, after the owner stated the architecture: `our (pxx) choice is to implement libraries in pascal by default, and have them importable to nilpy, transparently.' THERE IS NO MIMIC TO WRITE. The work is to add a PYTHON-SHAPED SURFACE TO lib/rtl/zlib.pas ITSELF, beside its existing Pascal one -- which is not a new pattern, it is what lib/rtl/base64.pas already does and what makes `import base64' work from NilPy TODAY (measured: b64encode/b64decode round-trip against CPython). base64 carries both surfaces in one unit: `Base64Encode(const data: TByteArray): AnsiString' for Pascal callers and `b64encode(const data: Variant): AnsiString' for Python ones. zlib.pas has only the first. The marshalling types are TPyBytes, TPyList and Variant, and a TPyBytes RETURN is already proven in the tree (mimic_urllib_error.pas: `function HTTPError.read(n: Integer): TPyBytes'), so `function decompress(const data: Variant): TPyBytes' is a supported spelling and not research. THIS ALSO DISSOLVES HALF THE BLOCKER: a Python face on zlib.pas needs no mimic_ precedence change at all, because zlib.pas IS the unit the owner's rule says `import zlib' should reach -- what still blocks it is only that the system C header wins today. Keep the slug for now so the blocked-by edge resolves; it names a mimic that should not exist. --- THE ORIGINAL FILING, which got the language right and the location wrong: THE OWNER'S STANDING INSTRUCTION, 2026-09-10: `notice that if lekkerzeilen has a missing library feature, we should craft a shim.` This is that, for zlib. MEASURED 2026-09-10: `import zlib` from NilPy reaches lib/rtl/zlib.pas and binds nothing, and the unit's own API is unusable from Python anyway -- InflateZlib wants hashing.pas's `TByteArray = array of Byte`, which NilPy has no spelling for (bytes, bytearray, list-of-int and return-lifted all answer `no overload matches`). So the shim must be PASCAL-side, for the same reason mimic_struct.pas gives for itself: the resolver is indifferent between mimic_X.pas and mimic_X.py and the one to pick is whichever language can do the job, and only Pascal can hold a TByteArray. SCOPE, derived from a real caller rather than from CPython's manual -- the way mimic_struct's subset was derived from lekkerzeilen's own world.py and capture.py: `decompress(data) -> bytes` is the whole requirement for a PNG decoder (chunk-walk, inflate, unfilter scanlines), so do that plus crc32, which the PNG chunk check needs and hashing.pas already has. BE HONEST ABOUT COMPRESSION: lib/rtl/zlib.pas only deflates as STORED blocks (DeflateZlibStored -- valid zlib, no compression), so a `compress` that round-trips is cheap and a `compress` that claims a ratio is a lie; ship the first and say so, or omit it. BLOCKED, and the edge is the point: the mimic_ fallback is consulted only after every ordinary lookup fails (pasparser_proc.inc:6500, its own comment), and lib/rtl/zlib.pas IS an ordinary lookup that succeeds -- so this file could be written today and never be reached. Do not work around that by naming it something else; the precedence is arm 2 of the blocker. WORTH KNOWING BEFORE RANKING THIS: neo-dd says it is moot for lekkerzeilen's FIRST use -- tiles are SQLite and the offline importer has PIL, so textures can be stored as raw RGBA and neither runtime decodes anything. The value is the PATTERN, not the PNG."
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
