---
slug: feature-n-the-struct-module
track: N
prio: 50
type: feature
status: backlog
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, stdlib, mimic, lekkerzeilen]
blocked-by: []
summary: "`import struct` fails with `no unit named struct and no shim mimic_struct`. Measured 2026-09-09 at compiler 418064fca1d3: it is now the FIRST wall in lekkerzeilen's `world` (the array module, which used to be that wall, was landed the same day) and is reached by `rd` and `capture` too. The mechanism is the mimic_ shim fallback and needs no compiler change -- a .pas shim, like mimic_array beside it, because the whole job is reinterpreting bytes as fixed-width numbers, which a .py shim can only do by hand-rolling IEEE-754. Measured surface, from the corpus and nothing beyond it: pack/unpack with byte-order prefixes '<', '>', '=', formats I, i, h, H, B, f, d, and a REPEAT COUNT ('%df' % n, built at run time), plus calcsize. Roughly the same size as mimic_array and shares its typecode table -- doing the two together is the reason to take this next."
---

# The struct module

`import struct` reaches no unit and no shim.

## Why it is next

`mimic_array` landed 2026-09-09 and cleared the array wall in `world.py`; the
module's next error is this one. That is the honest shape of the lekkerzeilen
blocker census — see the umbrella — and it is why this ticket exists rather than
the array one simply being reopened.

## Measured surface (lekkerzeilen, 2026-09-09)

```python
struct.pack(">I", len(payload))                       # rd.py
struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0) # rd.py
struct.pack("<h", 1) != struct.pack("=h", 1)          # world.py — endianness probe
struct.pack("<f", 1.0) != struct.pack("=f", 1.0)      # world.py
struct.unpack("<%df" % (len(verts) // 4), verts)      # scenery-side, RUN-TIME format
struct.unpack("<%dI" % (len(indices) // 4), indices)
```

So: byte-order prefixes `<` `>` `=`, formats `I i h H B f d`, and a repeat count
that is **computed at run time** — the format string is not a literal, so a
frontend-side compile-time format parser is not an option; the shim parses the
format at run time, as CPython does.

`unpack` returns a TUPLE, and both call sites wrap it in `list(...)`.

## Shape

A `.pas` shim (`lib/rtl/mimic_struct.pas`), for the reason `mimic_array` states
in its own header: the job is byte reinterpretation, which Pascal does with a
pointer cast and pure Python can only do by hand-rolling IEEE-754. The typecode
size/signedness table is the one `mimic_array.SetTc` already carries; the two
should share it rather than growing a second copy.

**The `=` vs `<` distinction is load-bearing and is not cosmetic**: world.py's
only use of struct is to ask whether the host is little-endian, by comparing the
two encodings. A shim that treated `=` as `<` would answer "never swap" on a
big-endian host and decode every terrain file backwards — silently, and only
there. Whatever else is subset, that comparison has to be real.
