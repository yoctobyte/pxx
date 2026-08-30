---
prio: 52
track: B
type: bug
blocked-by: []
summary: "Canvas.drawImage in lib/pcl/mimic_reportlab_pdfgen.pas calls pdf_add_image_file and throws the return code away. When pdfgen refuses the image -- an unsupported colour type, or today's byte-swapped PNG header -- the PDF is written, saved and reported OK with the image simply absent. The unit's stated policy is loud refusal; this is the one path that is silent."
status: new
owner: ""
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
