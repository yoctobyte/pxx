---
prio: 68
track: B
type: bug
blocked-by: []
summary: "lib/pcl/mimic_reportlab_lib_utils.pas declares `ImageReader.getSize: AnsiString` returning '', where reportlab returns a (width, height) pair. Any caller that unpacks it — `w, h = img.getSize()` — fails to COMPILE, taking the whole module with it. Blocks convertrawtext.py and SongFormatter.py."
status: done
owner: ""
---

# ImageReader.getSize returns a string where reportlab returns a pair

- **Type:** bug — **Track B** (`lib/pcl`, build with `$(PXX_STABLE)`, never
  rebuild the compiler). Filed 2026-08-30 by frankwasm from Track N while
  working [[bug-nilpy-render-backend-py-compile-does-not-terminate]]. **Not a
  compiler bug** — the compiler's refusal is correct.

## The declaration

`lib/pcl/mimic_reportlab_lib_utils.pas`:

```pascal
    function getSize: AnsiString;
...
function ImageReader.getSize: AnsiString;
begin
  { pdfgen measures the image itself when it embeds it; reportlab's callers use
    getSize to scale beforehand, which this subset does not support }
  getSize := '';
end;
```

reportlab's `ImageReader.getSize()` returns a **(width, height) pair**. Callers
unpack it. `songformatter/render_backend.py:114` does exactly that:

```python
w, h = img.getSize()
return Image.frombytes("RGB", (w, h), img.getRGBData())
```

```
render_backend.py:114: error: Nil Python: cannot unpack this value into
  several names — it is not a list, tuple or variant
```

The compiler is right: an `AnsiString` is none of those.

## Why the stub policy does not cover this one

The unit's header states the subset policy deliberately: a non-path source
"fails loudly at drawImage rather than drawing nothing". That is a good policy
and this is outside it. **`drawImage` fails at RUN time; `getSize` fails at
COMPILE time, in the caller, and takes the whole module with it.** A stub whose
TYPE is wrong is not a narrowed feature — it is a build break for every program
that touches the symbol, including programs that never call it on a path that
matters.

The rule this lands under: a stub may refuse to do the work; it may not lie
about its shape.

## Proposed fix, and it is already the house pattern

The sibling shim solves the identical problem — reportlab pagesizes are also
`(w, h)` pairs that Python unpacks. `lib/pcl/mimic_reportlab_lib_pagesizes.pas`:

```pascal
function Pair(w, h: Double): TPyList;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(w);
  l.append(h);
  Pair := l;
end;
```

So `getSize: TPyList` with two appended elements. **Measured, not proposed
blind** — with that shape applied locally, `convertrawtext.py` no longer stops
at `render_backend.py:114`. The experimental edit was reverted; `lib/pcl` is
Track B's and this ticket is the handoff, not a patch.

Whether the two elements can be the REAL dimensions is the open question and is
worth a look before defaulting to zeros: the vendored `lib/vendor/pdfgen` reads
PNG/JPEG/BMP headers already, so the numbers may be one exported accessor away.
Zeros compile and unpack, but a caller that scales by them gets a silent zero
rather than a loud refusal — which is the same class of defect one level down.
If zeros are what lands, say so at the declaration.

## Where it does NOT end

Fixing this does not make `convertrawtext.py` compile — it moves the wall to the
non-termination that
[[bug-nilpy-render-backend-py-compile-does-not-terminate]] is about. Measured:
with the pair shape applied, the same compile ran past **200s** without
finishing. Both are real and independent; this one is simply the first.

## What a fix must assert

- `w, h = ImageReader(path).getSize()` compiles and unpacks
- the value is usable as numbers, not merely unpackable
- `drawImage` with an `ImageReader` still behaves as the subset policy states
- `str(ImageReader(path))` still yields the path (`__str__` is what drawImage uses)

## Log
- 2026-08-30 — resolved, commit 1cf232bef.

---

## Resolution (2026-08-30, Track B)

`getSize: TPyList` returning a two-element pair, and the elements are the
**real** dimensions, not zeros.

The ticket's open question — "can the two elements be the REAL dimensions" —
was answered yes, but **not** through the obvious route. `pdf_parse_image_header`
is exactly the accessor the ticket predicted, and under pxx it returns
byte-swapped garbage: a valid 8x4 RGB PNG measures 134217728 x 67108864. That is
not a shim problem and chasing it here would have hidden it, so the unit reads
the headers itself (PNG IHDR, BMP, and the JPEG SOFn segment walk, ~110 lines)
and the byte-swap was split out as
[[bug-c-has-include-unsupported-so-pdfgen-selects-big-endian]].

`Pair` takes **Integers** here, unlike the pagesizes sibling's Doubles:
reportlab hands back PIL's `image.size`, a pair of ints, and `1024.0` where
CPython prints `1024` is a visible divergence at the boundary. Arithmetic is
unaffected either way — Variant widens.

An unreadable or unrecognised file **raises**, it does not answer `(0, 0)`.
The ticket flagged the trap and it is the right call: zeros unpack, scale a
drawing to nothing, and produce a wrong PDF with no diagnostic — the same
defect this ticket is about, one level down.

### The four assertions

```
w, h = ImageReader(path).getSize()   ->  unpacked 1024 1024
usable as numbers                    ->  2048 1025
drawImage over an ImageReader        ->  runs; PDF written; empty-source arm still raises
str(ImageReader(path))               ->  /home/neo/frankB/examples/adventure/scenes/cpu.png
```

Header reader vs `identify` as oracle: `png 1024x1024 (oracle 1024 x 1024)`,
`rgb 8x4 (oracle 8 x 4)`, missing file refused loudly.

**Third assertion, with a caveat worth reading.** `drawImage` over an
ImageReader behaves as the subset policy states — the path comes out through
`__str__`, the empty-source arm still raises — but the PDF it writes contains
**no image**, silently, because pdfgen refuses the file and the return code is
dropped. That is pre-existing and untouched by this fix; filed as
[[bug-b-drawimage-discards-pdfgens-error-and-writes-a-pdf-with-no-image]].

### Where the wall moves to

As the ticket predicted: `convertrawtext.py` still does not compile. The next
wall is [[bug-nilpy-render-backend-py-compile-does-not-terminate]].
