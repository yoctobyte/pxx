---
track: B
prio: 75
type: feature
blocked-by: []  # see FORK RESOLVED — this now belongs under the lekkerzeilen umbrella
summary: "The owner authorised lekkerzeilen to use PIL on 2026-09-12, mostly for PNG decoding. MEASURED FIRST, AND IT IS NOT A DECODER TICKET: lib/rtl/png.pas ALREADY decodes PNG — any valid deflate stream (stored, fixed and dynamic Huffman) and all standard RGBA scanline filters — over lib/rtl/zlib.pas, which is our own RFC 1950/1951 from scratch, with lib/rtl/image.pas holding the TImage/TRGBA core. So the work is a PIL-SHAPED PYTHON SURFACE over units we already have, exactly as base64.pas carries `b64encode` beside `Base64Encode`, plus adding png/image to PyRtlUnitServesPython in compiler/pasparser_proc.inc (the list today is ast atexit base64 collections configparser html io json markdown math pathlib random re subprocess tempfile tkinter zlib). Thirteen PIL members are reached across tools/ and tests/: Image.new, Image.open, Image.fromarray, Image.alpha_composite, Image.MAX_IMAGE_PIXELS, Image.LANCZOS, and the methods .size .tobytes .load .save .getpixel .resize .convert. THREE SCOPE LIMITS THAT ARE REAL WORK RATHER THAN SURFACE, each named below: png.pas handles ONLY non-interlaced 8-bit RGBA (colour type 6) while PIL opens palette, grayscale, 16-bit and interlaced, and lekkerzeilen's own png.py records palette PNGs being hit in practice; .resize with Image.LANCZOS needs a resampler that image.pas does not have; and Image.fromarray needs NUMPY, which is a far larger dependency than PIL and is out of scope here. FORK RESOLVED BY THE OWNER 2026-09-12, which is why this is p75 and not p55: he gave PIL permission because they were discussing TEXTURING, so it is a RUNTIME dependency and not offline tooling — "PIL is also one of them standard libraries. same for numpy btw". It therefore becomes a real closure wall the moment lekkerzeilen/ imports it, and numpy is a SIBLING in scope rather than the out-of-scope item the first draft of this ticket called it. HIS PREFERENCE IS TO BUILD PILLOW FOR REAL ("that would still be my preferred way of doing - just building the PIL wheel"), with his own caveat that it is "likely a recursive wasps nest" — MEASURED, and he is right for a sharper reason than size: see the measurement section, the recursion is that building a CPython C-API extension requires reproducing CPython's OBJECT LAYOUT, not 81 functions."
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


## MEASURED: why building Pillow is recursive, and it is not about size

Owner, 2026-09-12: *"we sortof concluded it may be easier to mimic a library
instead of actually building them - although that would still be my preferred
way of doing - just building the PIL wheel. or library. but that's likely a
recursive wasps nest"*.

Measured on this box (Pillow 12.1.1, numpy 2.3.5, CPython 3.14):

| | artefact size | distinct CPython C-API symbols | DT_NEEDED | `.so` in package |
| --- | --- | --- | --- | --- |
| `PIL/_imaging` | 486,712 | **81** | 7 | 6 |
| `numpy/_core/_multiarray_umath` | 9,270,336 | **312** | 6 | 19 |

**THE EXTERNAL HALF IS THE TRACTABLE HALF.** `_imaging` links `libtiff.so.6`,
`libjpeg.so.8`, `libopenjp2.so.7`, `libz.so.1`, `libimagequant.so.0`,
`libxcb.so.1`, `libc.so.6` — ordinary C libraries. pxx compiles C with cfront
and DT_NEEDED dynamic linking demonstrably works (the `--no-shims` zlib fixture
links `libz.so.1`). The META ticket calls class 2 *"the case pxx is unusually
good at"*. So libjpeg is WORK, not a nest.

**THE RECURSIVE HALF IS THE C-API, AND 81 UNDERSELLS IT BY CONSTRUCTION.**
`Py_INCREF` / `Py_DECREF` are **macros**: they write `op->ob_refcnt` directly, so
they appear in NO symbol table. The only refcount symbol in `_imaging` is
`_Py_Dealloc`, the out-of-line helper the DECREF macro tail-calls. So the
coupling is not to 81 functions — it is to **`PyObject`'s memory layout**:
`ob_refcnt`, `ob_type`, and the `tp_*` slots of every type object.

That is the recursion, stated precisely: **to build the library you must first
build the interpreter.** Not an approximation of it — a byte-compatible object
representation, because the extension's compiled code indexes those fields
directly. `nm` cannot see that, which is why the symbol count reads tractable.

So "mimic vs build" is not two sizes of the same job. Mimicking PIL is a
library-surface task over a decoder we already own. Building Pillow is the
CPython C-ABI project wearing a library's name, and it is recursive in the exact
sense the owner guessed.

**numpy is the same shape at four times the surface**, and it has an extra
property worth knowing before anyone scopes it: numpy publishes a C-ABI that
OTHER packages compile against, handed out as a function-pointer table through a
capsule rather than as dynamic symbols. My `nm --defined-only` probe for
`PyArray_*` returned 0 for exactly that reason — **that 0 is an instrument
artefact and must not be quoted as "numpy exports no C-ABI"**. Consequence:
mimicking numpy's PYTHON surface is bounded, while building numpy unlocks
nothing for the ecosystem unless that table is provided too.

**Recommendation, unchanged by the owner's preference and now with a reason:**
mimic the surface. His preferred route is not more expensive by a factor — it is
a different project, and its first deliverable is CPython.
