---
prio: 52
track: B
type: bug
blocked-by: []
summary: "Canvas.drawImage in lib/pcl/mimic_reportlab_pdfgen.pas calls pdf_add_image_file and throws the return code away. When pdfgen refuses the image -- an unsupported colour type, or today's byte-swapped PNG header -- the PDF is written, saved and reported OK with the image simply absent. The unit's stated policy is loud refusal; this is the one path that is silent."
status: done
owner: frankB
---

# `drawImage` discards pdfgen's error and writes a PDF with no image

- **Type:** bug — **Track B** (`lib/pcl`, build with `$(PXX_STABLE)`, never
  rebuild the compiler). Filed 2026-08-30 while working
  [[bug-b-imagereader-getsize-returns-a-string-where-reportlab-returns-a-pair]].

## The code

`lib/pcl/mimic_reportlab_pdfgen.pas`, `Canvas.drawImage`:

```pascal
  path := pystr_of(src);
  if path = '' then
    raise Exception.Create('reportlab shim: drawImage accepts a file path or an '
      + 'ImageReader over one; in-memory images are not in this subset');
  ...
  pdf_add_image_file(doc, nil, sx, sy, sw, sh, PChar(path));   { rc dropped }
```

The **in-subset** arm is loud, as the unit's policy says. The arm where pdfgen
itself refuses is silent: `pdf_add_image_file` returns a negative code and sets
an error string, and neither is read.

## Measured

```python
img = ImageReader("examples/adventure/scenes/cpu.png")
w, h = img.getSize()                       # 1024 1024 -- correct
c.drawImage(img, 50, 50, width=w/4, height=h/4)
c.drawString(50, 700, "drawImage over an ImageReader")
c.save()                                   # prints nothing, exits 0
```

The resulting PDF is 1615 bytes and contains the text run and **no image
object at all** — no `/XObject`, no `/Image`, no `/FlateDecode`. Underneath,
the same call in C:

```
pdf_add_image_file rc=-22 err="PNG has unsupported color type: 6"
```

That message is a true statement about pdfgen (it does not do RGBA) and the gcc
oracle returns exactly the same code for the same file. The defect is not that
the image was refused; it is that **nothing said so**, and the caller got a
document that looks finished.

## Two independent causes reach this same silence

1. **This ticket** — the return code is dropped, so *any* pdfgen refusal is
   invisible. Fixable now, in this file, no dependency.
2. **[[bug-c-has-include-unsupported-so-pdfgen-selects-big-endian]]** — pdfgen
   currently mis-reads every 32-bit PNG header field under pxx, so even PNGs it
   fully supports are refused (`"PNG chunk exceeds file: 218103808 vs 74"` on a
   valid 8x4 RGB PNG that gcc embeds with `rc=0`). Track C's, filed separately.

Fixing (2) makes correct PNGs work. Fixing (1) is what makes the *remaining*
failures — RGBA, malformed files, a missing path — say so instead of producing
a quietly wrong document. **Do (1) even after (2) lands**; it is the reason this
took a session to find.

## The fix

Read the return code and raise, in the same voice as the sibling arm:

```pascal
var rc: Integer;
...
  rc := pdf_add_image_file(doc, nil, sx, sy, sw, sh, PChar(path));
  if rc < 0 then
    raise Exception.Create('reportlab shim: drawImage could not embed "'
      + path + '": ' + <pdf_get_err text> + ' (pdfgen embeds PNG colour types '
      + '0/2/3, baseline JPEG and BMP)');
```

`pdf_get_err(doc, nil)` returns the message; it needs a declaration in the
unit's imported set if one is not already there. Check whether the other
`pdf_add_*` calls in this file drop their codes the same way — `drawString`,
`line`, `rect`, `circle` all return codes too, and this is a double-case: fix
the sibling arms in the same pass rather than leaving the next one to be found
the same expensive way.

## What a fix must assert

- `drawImage` over an RGBA PNG raises, and the message names the file and the reason
- `drawImage` over a path pdfgen accepts still succeeds and the PDF contains an image object
- the in-memory/empty-source arm still raises its existing message
- the other `pdf_add_*` call sites in the unit no longer drop a negative code

---

## Resolution (2026-08-30, Track B)

One free function, `PdfCheck(doc, rc, what)`, and **every** pdfgen call in the
unit now goes through it — the nine that dropped their codes and the three that
already checked, so error handling has one shape and one place that reads
pdfgen's message.

It is a free function in the implementation section rather than a method on
purpose: nothing a NilPy caller writes can reach it, so it adds no name to the
façade's Python-visible surface.

### The sites

| call | was | now |
| --- | --- | --- |
| `pdf_set_font` (ctor, default font) | dropped | checked |
| `pdf_append_page` (ctor) | dropped | nil-checked |
| `pdf_add_text` (drawString) | dropped | checked |
| `pdf_add_line` (line) | dropped | checked |
| `pdf_add_filled_rectangle` / `pdf_add_rectangle` (rect) | dropped | checked, both arms |
| `pdf_add_circle` (circle) | dropped | checked |
| `pdf_add_image_file` (drawImage) | dropped | checked |
| `pdf_set_font` (drawText, font restore) | dropped | checked |
| `pdf_append_page` (showPage) | dropped | nil-checked |
| `pdf_set_font` (setFont) | raised | via `PdfCheck`, message kept + pdfgen's reason appended |
| `pdf_get_font_text_width` (stringWidth) | swallowed | still answers 0, now **clears** the error |
| `pdf_save` (save) | raised | via `PdfCheck` |

`pdf_append_page` returns a `struct pdf_object *`, not an int, so those two are
nil-checks routed into the same helper.

### `stringWidth` is the one that still answers instead of raising

reportlab's `stringWidth` is called speculatively during layout and a zero is a
usable answer there, so the swallow is kept deliberately. What it did **not**
do is acknowledge the error, which is a real trap: pdfgen parks the message
until someone clears it, so the next genuine failure would report *this* call's
reason and send the reader to the wrong line. It now calls `pdf_clear_err`.

### Measured

Negative arm — the RGBA screenshot the ticket was filed over:

```
Unhandled exception: Exception: reportlab shim: drawImage could not embed
"…/examples/adventure/scenes/cpu.png" (pdfgen takes PNG colour types 0/2/3,
baseline JPEG and BMP) -- PNG has unsupported color type: 6
```

Both halves matter: ours names the file and the supported set, pdfgen's names
the actual reason. Previously this wrote a 1615-byte PDF containing the text
run, no image object, and exited 0.

Positive arm — and it is a **real** positive, not merely "did not raise".
BMP and JPEG are unaffected by
[[bug-c-has-include-unsupported-so-pdfgen-selects-big-endian]] (PNG is the only
one of the three with big-endian 32-bit header fields), so there is a format
that must still work today:

```
POS t.bmp 8 4 -> ok      ok_t.bmp.pdf  3722 bytes  /Image /XObject
POS t.jpg 8 4 -> ok      ok_t.jpg.pdf  4321 bytes  /Image /XObject /DCTDecode
```

`pdftotext` reads both pages back. Each of those documents also exercises
`drawString`, `line`, `rect(fill=1)`, `circle`, `showPage` and `save` — every
newly-checked site — so the checks are proven not to fire on the success path,
which is the way this class of change usually breaks.

Refusal arms, all three loud: unsupported colour type, empty/in-memory source
(the pre-existing message, unchanged), and a missing file.

**Stale-error control**, which is what `pdf_clear_err` is there for:

```
1: … unsupported font "NoSuchFont" (…) -- Invalid font name 'NoSuchFont'
2: … drawImage could not embed "…/no_such_file.bmp" (…) -- Unable to open …: No such fil
3: saved after two caught failures
```

Failure 2 reports **its own** reason, not failure 1's, and the Canvas is still
usable afterwards. Without the clear, line 2 would have echoed line 1.

(The truncation at `No such fil` is pdfgen's own `char errstr[128]`, reproduced
identically by a C-only probe — not our rendering.)

### Regression check

`make lib-test` green against stable v393, and the job that matters here is
**`reportlab-diff`** — the shim compared against **real reportlab** as the
oracle, extracted text plus per-word glyph boxes:

```
many_fonts   ok (5 words, worst delta 0.000029 pt)
positions    ok (4 words, worst delta 0.000029 pt)
text_fonts   ok (9 words, worst delta 0.000029 pt)
REPORTLAB DIFF: OK
```

That is a stronger statement than the repros above: those three documents drive
`setFont`, `drawString`, `showPage` and `save` repeatedly, and every one of them
is now a checked call. A check that fired spuriously on a success path would
have taken this job red, and it did not — measured against reportlab's own
output rather than against my own expectation of it.

The three tests that touch the shim (`test_nilpy_dotted_package_import`,
`test_nilpy_typed_const_import`, `test_nilpy_dispatch_result_class`) compile,
run and produce unchanged output; none reaches `drawImage`.

Nothing here depends on the endian bug. When
[[bug-c-has-include-unsupported-so-pdfgen-selects-big-endian]] lands, PNG joins
BMP and JPEG on the success path and the refusals that remain — RGBA, malformed
files, missing paths — keep saying so.

## Log
- 2026-08-30 — resolved, commit db68102cd.
