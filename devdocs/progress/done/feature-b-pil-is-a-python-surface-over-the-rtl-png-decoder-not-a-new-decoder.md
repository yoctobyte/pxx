---
track: B
prio: 75
type: feature
blocked-by: []  # see FORK RESOLVED — this now belongs under the lekkerzeilen umbrella
summary: "RESOLVED 2026-09-14 (frankb-56). lib/rtl/pil.pas serves `from PIL import Image' (`pil' added to PyRtlUnitServesPython) and EVERY ROW of test/lib_pil_pillow.py is BYTE-IDENTICAL to Pillow 12.1.1, which is installed here and is the oracle in make lib-test -- getpixel, convert, tobytes, crop, alpha_composite, nine resize combinations over three filters, save/open round trip, and decoding all seven PNG colour types Pillow can write. BOTH REAL SCOPE LIMITS ARE DISCHARGED: png.pas now decodes colour types 0/2/3/4/6 at every legal bit depth with PLTE and tRNS (palette was the case lekkerzeilen actually hits) and refuses interlaced BY NAME; and NEAREST/BILINEAR/LANCZOS all exist and are byte-exact. fromarray/numpy stays out of scope. FOUR CORRECTIONS TO THIS TICKET'S OWN NUMBERS, re-derived from the six PIL-importing files as it asked: `.load' is NOT a PIL member (every one is json.load, so the list of 13 has 12 in it); `.size' is 3 uses not 31; ImageDraw IS used by two files and is deferred-because-tooling rather than speculative; and Image.open(io.BytesIO) is used and is refused loudly here. TWO COMPILER BUGS FOUND AND FILED WITH REDUCTIONS THAT CONTAIN NO PIL: a class var declared before an instance field is counted into the INSTANCE layout so two live objects OVERLAP (p80, silent, this is what made resize segfault) and a class named after a used unit cannot be constructed from outside it (p45, loud). Both worked around at the declaration in pil.pas and registered in track-b-workarounds.md. THREE PLACES THE OBVIOUS IMPLEMENTATION WAS WRONG AND ONLY THE ORACLE CAUGHT IT: convert('RGB') DROPS alpha rather than compositing onto black; resize PREMULTIPLIES alpha (a 2x1 opaque-red-beside-transparent-blue reduced to 1x1 is (255,0,0,128) in Pillow and (127,0,127,127) under straight averaging) -- and a comment here asserted the opposite from assumption; and a fully opaque fixture cannot see either, so the fixture carries a hard alpha edge and the positive control reddens six rows. STILL OPEN AND STATED: ImageDraw, numpy, file-object open, interlaced, and convert('1') dithering which matches 16 of 18 bytes at the trailing edge (searched, not assumed). png and image were deliberately NOT added to PyRtlUnitServesPython though this ticket asked -- `import png' resolves to /usr/include/png.h today, and adding it would swap a wrong answer for a useless one since png.pas has no Python surface. NO LONGER INERT -- pin v411 CARRIES IT and the row was verified RUNNING and byte-identical on 2026-09-19 (32 rows, Pillow 12.1.1, under the PINNED compiler); the clause that follows is kept as the history of why it once skipped: `from PIL import Image' needs `pil' on PyRtlUnitServesPython, which is a COMPILER change, and lib-test builds with $(PXX_STABLE) -- pin v409 predates it, so the pinned compiler refuses the import. The differential SKIPS LOUDLY (and is recorded in lib-test's SKIPPED list) rather than going red or reading as a pass, and the skip is a behavioural probe of the pinned compiler rather than a version check, so it starts running by itself at the next pin with nothing to remember. Everything above was measured with the LIVE compiler. THE FORK IS UNCHANGED: PIL still appears only in tools/ and tests/, so this is still not wired to the lekkerzeilen umbrella."
status: done
owner: frankb-56
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

## CORRECTION TO THIS TICKET'S OWN FRAMING (owner, 2026-09-12)

> *"you did notice we just implemented png and zlib from scratch. or TLS."*

This ticket said "mimic the surface over a decoder we already own", which
undersells what that decoder IS and draws the line in the wrong place. **We do
not avoid implementing. We avoid the CPython C-ABI.** The inventory, measured:

    lib/rtl/zlib.pas                965    RFC 1950/1951 inflate, no libz
    lib/rtl/png.pas                 330    PNG codec over it
    crypto + TLS, 13 units        3,114    AES-GCM, ECDSA P-256, RSA,
                                           SHA-256/512, X.509, and a TLS 1.3
                                           handshake (X25519 ECDHE + key
                                           schedule) in tls13_native.pas

**A TLS 1.3 stack with its own X.509 parser is a harder job than a JPEG
decoder.** So "can we implement an image codec from scratch" is already answered
yes, repeatedly, and nothing in this ticket should read as doubting it.

**The line is therefore NOT mimic-vs-implement. It is:**

| | verdict | why |
| --- | --- | --- |
| implement an ALGORITHM from scratch in Pascal | **done routinely** — deflate, PNG, AES-GCM, X.509, TLS 1.3 | bounded, testable against a spec and an oracle |
| expose it under a Python-shaped name | **the cheap part** — `base64.pas` pattern | one unit, two surfaces |
| port a CPython C-API extension | **the wasps nest** | couples to `PyObject`'s MEMORY LAYOUT, not to a function list — `Py_INCREF` is a macro writing `ob_refcnt`, so building it means building an interpreter first |

So if `Image.open` eventually needs JPEG, **writing a JPEG decoder in Pascal is
the in-house move, not a defeat** — the same route that produced `png.pas` over
`zlib.pas`. What stays refused is reproducing `_imaging` as a CPython extension.

Restating the recommendation with the line in the right place: mimic PIL's
**surface**; implement whatever **algorithm** it needs from scratch as the need
is measured; never port the extension.

## RESOLVED 2026-09-14 (frankb-56, Track B)

`lib/rtl/pil.pas` serves `from PIL import Image`, and **every row of
`test/lib_pil_pillow.py` is byte-identical to Pillow 12.1.1**, which is
installed on this machine and is used as the oracle in `make lib-test`.

### What the ticket asked for, and what happened to its three scope limits

| the ticket's limit | outcome |
| --- | --- |
| 1. `png.pas` is non-interlaced 8-bit RGBA only; palette PNGs are hit in practice | **DONE.** It now decodes colour types 0, 2, 3, 4 and 6 at every bit depth the spec allows (1/2/4/8/16 as applicable), with PLTE and tRNS. Verified against Pillow-written files of every one. Interlaced (Adam7) is refused **by name** |
| 2. `.resize` + `Image.LANCZOS` needs a resampler `image.pas` does not have | **DONE.** NEAREST, BILINEAR and LANCZOS, all byte-exact against Pillow |
| 3. `Image.fromarray` needs numpy | **still out of scope**, as the ticket said |

### Four corrections to this ticket's own measurements

The ticket said to re-derive the member list from the PIL-importing files
before ranking on volume. Done, and it moved:

- **`.load` is not a PIL member at all.** Every `.load` in those files is
  `json.load`. The ticket's list of thirteen has twelve members in it.
- **`.size` is real but rare** — 3 uses on PIL images (`tools/fronts.py:98`,
  `tools/texture.py:508`, `tests/test_icon.py:48`), not the 31 the grep
  suggested; the rest are numpy arrays.
- **`ImageDraw` IS used and is not speculative.** `tools/icon.py` and
  `tools/import_nl.py` both write `from PIL import Image, ImageDraw` and call
  `.polygon` / `.rounded_rectangle`. The ticket's *"should not be added
  speculatively"* is right about the priority and wrong about the facts: it is
  deferred because both callers are offline tooling, not because nobody uses it.
- **`Image.open(io.BytesIO(...))` is used** (`tools/import_nl.py:88`). We take a
  path only, and refuse a file object loudly rather than returning a wrong
  picture.

### Two compiler bugs found on the way, both filed with reductions

Neither is about PIL; both were reduced to units with no library in them.

- [[bug-a-a-class-var-declared-before-an-instance-field-corrupts-the-instance-layout]]
  — **p80, silent memory corruption.** A `class var` before an instance field is
  counted into the INSTANCE layout, so two live objects overlap and constructing
  the second reinitialises the first. This is what made `im.resize(...)`
  segfault: the constructor emptied the image being resized. Four rows locate
  it; three plausible reductions do *not* reproduce it and are recorded so a
  fixer does not spend them again.
- [[bug-a-a-class-named-after-a-used-unit-cannot-be-constructed-from-outside-that-unit]]
  — p45, loud. `Image.Create(...)` is `undefined variable (Create)` when the
  unit also uses `image`. Both names are forced from outside, so the collision
  cannot be designed away.

Both are worked around in `pil.pas` at the declaration, with the reason at the
site, and registered in `devdocs/dev/track-b-workarounds.md` with revert
instructions.

### Three places the obvious implementation was wrong, caught only by the oracle

Worth recording because each is a *plausible* answer that a round-trip or
self-consistency test would have certified:

1. **`convert("RGB")` drops alpha; it does not composite onto black.** We
   composited. Only fully transparent pixels differed — Pillow keeps their
   colour.
2. **`resize` premultiplies alpha.** We resampled channels independently and had
   written a comment asserting that this was Pillow's behaviour. It is not. The
   one-line proof: a 2x1 image of opaque red beside *transparent* blue, reduced
   to 1x1 bilinear, is `(255, 0, 0, 128)` in Pillow and `(127, 0, 127, 127)`
   under straight averaging — the invisible blue bleeding halfway in.
3. **A fully opaque fixture cannot see (2).** Both implementations agree on it,
   so the fixture deliberately carries a hard alpha edge, and the positive
   control (disabling the premultiply) reddens six rows.

Also: `Luma` must round, not truncate; mode `"1"` pixels read back as 0/255 and
not 0/1; and `MAX_IMAGE_PIXELS` is 89478485, not the 178956970 written here from
memory.

### What is NOT done, stated plainly

- **`ImageDraw`** — measured as used by two tooling files. A scanline rasteriser
  is a day's work; deferred, not refused.
- **`Image.fromarray` / numpy** — out of scope, per the ticket.
- **`Image.open` of a file object** (`io.BytesIO`) — refused loudly.
- **Interlaced (Adam7) PNG** — refused by name.
- **`convert("1")` dithering is not byte-exact** — 16 of 18 bytes on the
  fixture; the trailing edge of the last rows differs. Searched rather than
  assumed (clamping changes nothing, floor and float accumulation both score
  11/18), so truncating division is right and the gap is Pillow's boundary
  carry, which is not readable on this machine. Nothing in the corpus calls it.
- **`png` and `image` were deliberately NOT added to `PyRtlUnitServesPython`**,
  though the ticket asked for both. Measured: `import png` today resolves to
  `/usr/include/png.h`, compiles green, and fails at exec looking for a
  `libpng.so` nobody declared. Adding `png` would swap that silent wrong answer
  for a resolution to `lib/rtl/png.pas`, which has **no Python surface at all** —
  every entry point takes `hashing.TByteArray`, which NilPy cannot spell. So the
  trade is a wrong answer for a useless one. `pil.pas` is the Python face for
  both units, and the host-header fallthrough belongs to
  [[bug-n-a-bare-nilpy-import-falls-through-to-a-host-c-header-of-the-same-name-and-says-nothing]].

### The fork this ticket raised is unchanged by the work

*"Do we want the runtime to decode PNG through a PIL-shaped surface, or is PIL
only ever for the offline importer and the tests?"* — still open, and still not
wired to the lekkerzeilen umbrella. The measurement that bears on it: PIL appears
in `tools/` and `tests/` only, in all six importing files, exactly as this ticket
recorded. Nothing found today moves that.

### INERT UNTIL THE NEXT PIN, and this is the part a reader must not miss

`from PIL import Image` needs `pil` on `PyRtlUnitServesPython` in
`compiler/pasparser_proc.inc`. That is a COMPILER change, and `make lib-test`
builds with `$(PXX_STABLE)` — **pin v409 predates it**, so under the pinned
compiler the import is refused with *"pil is the Pascal unit lib/rtl/pil.pas,
not a Python module"*.

So the differential row **skips loudly** until a pin carries the entry. It does
not go red, and it does not read as a pass: it prints
`PIL SKIP -- the pinned compiler cannot resolve ...` and records
`pil-vs-pillow` in lib-test's own SKIPPED list, which the final summary line
reproduces.

**The skip is a behavioural probe, not a version check.** The recipe asks the
pinned compiler to compile a two-line `from PIL import Image` and branches on
the answer, so the row starts running by itself at the next pin with nothing for
anyone to remember or revert. Everything measured in this resolution was
measured with the LIVE compiler, where all 30 rows are identical to Pillow
12.1.1.

This is the cost CLAUDE.md names: a fix is inert until pinned, and a compiler
change a `lib/**` file depends on has to say so at closing time. Saying it.

## Log
- 2026-09-14 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6b45b991b.

## The inert-until-pinned caveat is DISCHARGED (2026-09-19, frankD)

This ticket's own closing section said the differential would skip until a pin
carried `pil` in `PyRtlUnitServesPython`, and asked a later reader to check.
Checked, and it has cleared:

- The behavioural probe now PASSES -- `stable_pinned` compiles `from PIL import
  Image; print(Image.LANCZOS)`, so the recipe takes its live arm instead of the
  skip arm. Nothing had to be remembered or reverted, exactly as designed.
- `lib/rtl/pil.pas` builds under the PIN (`-Fulib/rtl`).
- The differential runs **32 rows and is byte-identical to Pillow 12.1.1**,
  measured under the pinned compiler rather than the live one -- which is the
  claim the original resolution could NOT make and said so.

Pin in place when measured: v411. Nothing else in this ticket changed; the open
items below (ImageDraw, numpy/fromarray, file-object open, interlaced,
convert("1") dithering) are untouched and still open.

Recorded because a stale caveat is the expensive kind: a reader who obeys
"inert until the next pin" produces no signal that it was wrong, and this one
would have sent the next seat looking for a pin that had already happened.
