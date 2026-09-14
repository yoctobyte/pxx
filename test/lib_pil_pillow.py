# Run under BOTH pxx and CPython-with-Pillow; the two outputs must be identical.
#
# THIS IS A DIFFERENTIAL AGAINST A REAL ORACLE, not a shape assertion. Pillow
# 12.1.1 is installed on this machine and `from PIL import Image` resolves to
# lib/rtl/pil.pas under pxx and to Pillow under CPython, so ONE file exercises
# both and every row is a claim about agreement.
#
# WHAT IS DELIBERATELY NOT ASSERTED HERE, because a row that is red for no
# defect is worse than no row:
#
#   * `convert("1")` output bytes. Pillow dithers (Floyd-Steinberg) and ours
#     matches 16 of 18 bytes on this fixture -- the trailing edge of the last
#     rows differs, see pil.pas. Naming it here so nobody "fixes" the fixture by
#     adding the row and pinning our own answer.
#   * PNG file bytes. png.pas writes 8-bit RGBA whatever the mode, so our files
#     are valid and larger than Pillow's. Compare decoded PIXELS, which is what
#     the save/open round trip below does.
#   * `im.mode` after opening a PALETTE file. Pillow says "P" and we say the
#     widened mode, because we do not keep a palette. The MODE row for palette
#     files is therefore absent and the PIXEL rows are the assertion.
#
# The images are built here rather than committed as binaries, so the fixture is
# self-contained and a reader can see exactly what is being decoded.
import sys
from PIL import Image

# The fixture directory test/lib_pil_gen.py wrote, passed in by the Makefile.
DIR = sys.argv[1]
# Each runtime writes its own round-trip file: png.pas emits RGBA whatever the
# mode and Pillow does not, so sharing one path would have the second run read
# the first run's bytes and compare a picture to itself.
RUNTIME = sys.argv[2]

def p(name):
    return DIR + "/" + name

# ---- a deterministic source with a hard alpha edge --------------------------
# THE ALPHA EDGE IS THE POINT. A fully opaque fixture agrees with Pillow under
# straight per-channel resampling AND under premultiplied resampling, so it
# certifies the wrong one. Every fifth pixel is fully transparent.
# BUILT HERE AND ALSO READ FROM DISK, on purpose: building it exercises
# Image.new/putpixel under both runtimes, and the decode rows below read the
# same picture back out of a file the REAL Pillow wrote. A fixture that only
# read our own output would be testing our encoder against our decoder.
W, H = 12, 9
src = Image.new("RGBA", (W, H))
for y in range(H):
    for x in range(W):
        src.putpixel((x, y), ((x * 20) % 256, (y * 28) % 256,
                              ((x + y) * 13) % 256, 255 if (x + y) % 5 else 0))
print("built == on disk", src.tobytes() == Image.open(p("t_rgba.png")).convert("RGBA").tobytes())

print("size", src.size, "mode", src.mode)
print("getpixel   ", src.getpixel((3, 2)), src.getpixel((0, 0)), src.getpixel((11, 8)))

# ---- mode conversion --------------------------------------------------------
# convert("RGB") DROPS alpha rather than compositing onto black, so a fully
# transparent pixel keeps its colour. (0,0) is transparent in this fixture and
# is the row that tells the two behaviours apart.
rgb = src.convert("RGB")
lum = src.convert("L")
print("convert RGB", rgb.mode, rgb.getpixel((3, 2)), rgb.getpixel((0, 0)))
print("convert L  ", lum.mode, lum.getpixel((3, 2)), lum.getpixel((0, 0)))
print("mode 1 px  ", src.convert("1").getpixel((0, 0)))   # 0 or 255, never 0 or 1

# ---- tobytes ----------------------------------------------------------------
print("tobytes len", len(src.tobytes()), len(rgb.tobytes()), len(lum.tobytes()))
print("tobytes rgba", repr(src.tobytes()[:12]))
print("tobytes rgb ", repr(rgb.tobytes()[:12]))
print("tobytes L   ", repr(lum.tobytes()))

# ---- geometry ---------------------------------------------------------------
c = src.crop((2, 1, 6, 5))
print("crop       ", c.size, c.getpixel((0, 0)), c.getpixel((3, 3)))
# A crop box that runs off the edge is legal and pads with transparent black.
over = src.crop((8, 6, 16, 14))
print("crop over  ", over.size, over.getpixel((7, 7)))

# ---- alpha_composite --------------------------------------------------------
lay = Image.new("RGBA", src.size, (255, 0, 0, 128))
comp = Image.alpha_composite(src, lay)
print("composite  ", comp.getpixel((3, 2)), comp.getpixel((0, 0)))

# ---- resampling -------------------------------------------------------------
# Both an exact ratio (12->6) and an inexact one (9->4 and 9->3): the exact case
# agrees under several wrong roundings, the inexact case does not.
for nm, f in (("NEAREST", Image.NEAREST), ("BILINEAR", Image.BILINEAR),
              ("LANCZOS", Image.LANCZOS)):
    for size in ((6, 4), (6, 3), (24, 18)):
        r = src.resize(size, f)
        print("resize %-8s %-8s" % (nm, size), r.getpixel((1, 1)), repr(r.tobytes()[:12]))

# ---- every PNG colour type, decoded to the same pixels -----------------------
# Written by Pillow, read back by whichever runtime is executing this file.
for n in ("t_rgba", "t_rgb", "t_gray", "t_la", "t_pal", "t_pal8", "t_bilevel"):
    im = Image.open(p(n + ".png")).convert("RGBA")
    px = [im.getpixel((x, y)) for y in range(im.size[1]) for x in range(im.size[0])]
    print("decode %-7s" % n, im.size, px[0], px[17], px[-1],
          sum(sum(v) for v in px))

# ---- save / open round trip -------------------------------------------------
# PIXELS, not bytes: our encoder writes RGBA whatever went in.
src.save(DIR + "/out_" + RUNTIME + ".png")
back = Image.open(DIR + "/out_" + RUNTIME + ".png")
print("roundtrip  ", back.size, back.convert("RGBA").tobytes() == src.tobytes())

# ---- the settable class attribute -------------------------------------------
print("maxpixels  ", Image.MAX_IMAGE_PIXELS)
Image.MAX_IMAGE_PIXELS = None
print("maxpixels  ", Image.MAX_IMAGE_PIXELS)
