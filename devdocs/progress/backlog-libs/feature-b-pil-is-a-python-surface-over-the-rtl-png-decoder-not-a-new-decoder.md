---
track: B
prio: 55
type: feature
blocked-by: []
summary: "The owner authorised lekkerzeilen to use PIL on 2026-09-12, mostly for PNG decoding. MEASURED FIRST, AND IT IS NOT A DECODER TICKET: lib/rtl/png.pas ALREADY decodes PNG — any valid deflate stream (stored, fixed and dynamic Huffman) and all standard RGBA scanline filters — over lib/rtl/zlib.pas, which is our own RFC 1950/1951 from scratch, with lib/rtl/image.pas holding the TImage/TRGBA core. So the work is a PIL-SHAPED PYTHON SURFACE over units we already have, exactly as base64.pas carries `b64encode` beside `Base64Encode`, plus adding png/image to PyRtlUnitServesPython in compiler/pasparser_proc.inc (the list today is ast atexit base64 collections configparser html io json markdown math pathlib random re subprocess tempfile tkinter zlib). Thirteen PIL members are reached across tools/ and tests/: Image.new, Image.open, Image.fromarray, Image.alpha_composite, Image.MAX_IMAGE_PIXELS, Image.LANCZOS, and the methods .size .tobytes .load .save .getpixel .resize .convert. THREE SCOPE LIMITS THAT ARE REAL WORK RATHER THAN SURFACE, each named below: png.pas handles ONLY non-interlaced 8-bit RGBA (colour type 6) while PIL opens palette, grayscale, 16-bit and interlaced, and lekkerzeilen's own png.py records palette PNGs being hit in practice; .resize with Image.LANCZOS needs a resampler that image.pas does not have; and Image.fromarray needs NUMPY, which is a far larger dependency than PIL and is out of scope here. ONE FORK FOR THE OWNER, stated in the body: today PIL appears ONLY in tools/ and tests/ and NOT once in the lekkerzeilen/ runtime package, so on the standing 'we don't care compiling tooling right now' this buys nothing yet — the prio assumes the authorisation is forward-looking."
---

# PIL is a Python surface over the RTL PNG decoder, not a new decoder

Owner, 2026-09-12: *"i authorized lekkerzeilen to use the PIL library. mostly
for PNG decoding.. so, we might as well craft a ticket out of that - mimic PIL
library"*.

The crash course's own lesson applies here and is why this ticket is small: a
seat once spent an evening proposing a mechanism that already existed. **Grep
before proposing.** What the grep found:

| we already have | what it does |
| --- | --- |
| `lib/rtl/png.pas` | PNG encode **and decode**; decode accepts any valid deflate stream (stored / fixed Huffman / dynamic Huffman) and implements all standard PNG scanline filters for RGBA |
| `lib/rtl/image.pas` | `TImage`, `TRGBA`, `ImageInit/Free/SetPixel/GetPixel/InBounds/PixelCount` |
| `lib/rtl/zlib.pas` | RFC 1950 / 1951 inflate, from scratch, no libz |

So the decoding the owner cares about is **done, in Pascal, today**. What is
absent is the Python-facing half.

## The pattern to copy is `base64.pas`, and it is one unit not two

`lib/rtl/base64.pas` carries BOTH surfaces in one unit — `Base64Encode` for
Pascal callers and `b64encode(const data: Variant)` for Python ones, with a
comment explaining that CPython's takes bytes. **There is no `mimic_` to write
for a library we already have** (crash course, and the owner overruled
`python-libraries.md` §2 on shims being a last resort).

Two mechanical steps:

1. Add PIL-shaped entries to `png.pas` / `image.pas` (or one new unit that uses
   both), marshalling through `TPyBytes` / `TPyList` / `Variant`.
2. Add `png` and `image` to `PyRtlUnitServesPython` in
   `compiler/pasparser_proc.inc`. Today's list: `ast atexit base64 collections
   configparser html io json markdown math pathlib random re subprocess
   tempfile tkinter zlib`.

See [[feature-n-mimic-zlib-gives-nilpy-cpythons-decompress-over-the-rtl-inflater]]
— the same shape for `zlib`, and whoever does that should probably do this.

## The member surface, measured

Thirteen distinct PIL members across `tools/` and `tests/`:

    Image.new   Image.open   Image.fromarray   Image.alpha_composite
    Image.MAX_IMAGE_PIXELS   Image.LANCZOS
    .size   .tobytes   .load   .save   .getpixel   .resize   .convert

**The per-member counts are an UPPER BOUND and must not be quoted as PIL
counts.** They came from a grep over every `.py` in `tools/ tests/
lekkerzeilen/`, and `.size` (31) and `.load` (19) are spellings any object can
carry. The distinct NAME list is reliable; the tallies are not. Re-derive from
the PIL-importing files alone — `tools/icon.py`, `tools/import_nl.py`,
`tests/test_icon.py`, `tests/test_import.py` — before ranking on volume.

## `from PIL import Image` is a PACKAGE import, which is the structural risk

Every call site spells it `from PIL import Image` — a package with a submodule,
not a flat module. That is a different shape from `import zlib`, and it is the
one part of this ticket that may turn out to be frontend work rather than
library work. **Establish that spelling resolves before building a surface
behind it**, or the surface is unreachable and the fixture will pass for the
wrong reason.

## Three things that are real work, not surface

1. **Colour types.** `png.pas` is non-interlaced 8-bit RGBA (type 6) only. PIL
   opens palette (3), grayscale (0), grayscale+alpha (4), truecolour (2),
   16-bit and interlaced. This is not hypothetical: `lekkerzeilen/png.py:147`
   records *"PIL reaches for that the moment a palette fits -- the first real
   PNG file tripped it"*, and `:170` has PIL writing a one-entry palette with
   `optimize=True`. So `Image.open` on a real PIL-written file meets PLTE early.
2. **`.resize` + `Image.LANCZOS`.** `image.pas` has no resampler at all.
3. **`Image.fromarray`** takes a numpy array. `tools/import_nl.py`,
   `tests/test_import.py` and `tests/test_culling.py` all use numpy.
   **Out of scope — numpy is a far bigger dependency than PIL** and wants its
   own ticket if anyone ever needs it.

One encode-side divergence to record rather than fix: `PngEncodeRGBA` writes
zlib streams made of **uncompressed** deflate blocks, so `.save()` output is
valid PNG and much larger than PIL's. Correct, not defective — and a fixture
comparing file BYTES against PIL would fail for that reason alone. Compare
decoded pixels.

## THE FORK, and it decides the prio rather than the design

**PIL appears nowhere in the `lekkerzeilen/` runtime package — only in `tools/`
and `tests/`.** Verified: the apparent runtime hits are `PILE_STEP`,
`COMPILE_STATUS` and comments in `png.py` mentioning PIL, not imports. And
`lekkerzeilen/png.py`'s own docstring says *"Nothing in the runtime needs this.
The importer decodes offline where PIL is allowed, and tiles carry raw RGBA, so
no texture path goes through here."*

Against the standing *"notice that we don't care compiling tooling right
now"*, that means this buys nothing for the entry-point closure today.

> **The question, in goal terms: do we want the runtime to decode PNG through a
> PIL-shaped surface, or is PIL only ever for the offline importer and the
> tests?**

If the runtime is to use it, this becomes a blocker of
[[umbrella-lekkerzeilen-compiles-and-runs-under-nilpy]] the moment
`lekkerzeilen/` imports it, and the prio should rise. If PIL stays offline
tooling, 55 is generous and this is a convenience. **Not wired to that umbrella
yet, deliberately** — wiring it would inflate it to the umbrella's 90 on a
dependency no closure reaches.

## This is not a new strategy — it INSTANTIATES the one already decided

[[feature-nilpy-thirdparty-libraries-as-targets]] (`unfinished/`, N p65) is the
META ticket that classifies third-party Python libraries and picks a strategy per
class. **Pillow is its class 3 — CPython C-API extension**: it ships
`_imaging.cpython-*.so`, built against `Python.h`, wheel tag
`cp312-manylinux_x86_64`.

And that ticket's prescribed strategy for class 3 is this ticket, in its own
words:

> **the wall.** Either mimic the module's SURFACE in `lib/` (our own
> implementation behind the same API), or do without

So "mimic PIL" is not a preference and not an invention — it is the documented
play for the class Pillow belongs to, and **compiling Pillow is explicitly not
on the table.** Worth stating because the cheap-looking alternative (compile the
dependency as source, class 1) is unavailable here and someone will reach for it.

The owner's own framing — *"mostly for PNG decoding"* — narrows it further and
favourably: we are not mimicking Pillow, we are exposing **one** of its modules
over a decoder we already own. `Image` is the whole surface asked for;
`ImageDraw`, `ImageFont`, `ImageFilter` and the rest are not in scope and should
not be added speculatively.

Cross-check before starting: that META ticket is flagged `STALE-PARK-HELD` by
`tools/progress.sh check` — its prose names four now-resolved tickets near a
blocking phrase. Per CLAUDE.md, `owner:` is attribution and not a claim, so read
it before treating it as blocked, and the stale edges are not a reason to wait.
