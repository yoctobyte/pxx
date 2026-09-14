# CPython + Pillow ONLY. Writes the PNG fixtures that test/lib_pil_pillow.py
# reads under both runtimes.
#
# SEPARATE FROM THE DIFFERENTIAL FOR TWO REASONS, both of which bit when the two
# were one file. The palette files have to be written by the REAL Pillow in both
# runs -- a palette PNG we wrote ourselves would test our encoder against our
# decoder and could agree while both were wrong. And the calls that make them
# (`convert("P", palette=...)`, `quantize(colors=8)`) are Pillow-only and take
# KEYWORD arguments, which NilPy does not have, so the differential cannot
# contain them at all.
import sys
from PIL import Image

out = sys.argv[1]
W, H = 12, 9
src = Image.new("RGBA", (W, H))
for y in range(H):
    for x in range(W):
        src.putpixel((x, y), ((x * 20) % 256, (y * 28) % 256,
                              ((x + y) * 13) % 256, 255 if (x + y) % 5 else 0))

src.save(out + "/t_rgba.png")                                    # colour type 6
src.convert("RGB").save(out + "/t_rgb.png")                      # type 2
src.convert("L").save(out + "/t_gray.png")                       # type 0
src.convert("LA").save(out + "/t_la.png")                        # type 4
src.convert("P", palette=Image.ADAPTIVE).save(out + "/t_pal.png")        # type 3
src.quantize(colors=8).save(out + "/t_pal8.png", optimize=True)          # type 3 + tRNS
src.convert("1").save(out + "/t_bilevel.png")                    # type 0, depth 1
# 16-bit grayscale, which no other row reaches and which png.pas must truncate
# to the high byte rather than refuse.
Image.new("I;16", (W, H), 0).point(lambda v: 0).convert("I;16").save(out + "/t_g16.png")
print("generated")
