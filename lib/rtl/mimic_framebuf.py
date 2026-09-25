"""mimic_framebuf -- MicroPython's `framebuf`: drawing into a bytearray that a
display driver then sends to the panel. `import framebuf` resolves here through
the NilPy import resolver's `mimic_` fallback.

WHY IT EXISTS. The common MicroPython display drivers are written against it
and are compiled here unchanged: micropython-lib's ssd1306 SUBCLASSES
FrameBuffer (`class SSD1306(framebuf.FrameBuffer)`), and max7219 builds one and
re-exports its bound methods. So the surface is the class, its constants and
its drawing methods, with MicroPython's names, argument order and pixel
packing -- a driver sends `self.buffer` to the panel byte for byte, so the
packing IS the interface, not an implementation detail.

THE PACKING, per format (from MicroPython's extmod/modframebuf.c):
  MONO_VLSB  one bit per pixel, a byte is 8 pixels in a COLUMN, bit 0 at the top
             (SSD1306 page layout): byte (y // 8) * stride + x, bit y % 8.
  MONO_HLSB  one bit per pixel, a byte is 8 pixels in a ROW, bit 7 leftmost
             (MAX7219): byte (x + y * stride) // 8, bit 7 - x % 8.
  MONO_HMSB  as HLSB with bit 0 leftmost.
  RGB565     two bytes per pixel, little-endian.
  GS2_HMSB, GS4_HMSB, GS8  2, 4 and 8 bits per pixel, row-major.
For the packed mono and grey formats the stride is rounded up to a whole byte,
as MicroPython does.

text() uses MicroPython's own 8x8 font, vendored in mimic_framebuf_font.py
(MIT; see lib/rtl/THIRD-PARTY.md).

ABSENT: ellipse() and poly(), which none of the census drivers call.
Everything else, clipping included, follows modframebuf.c.
"""

from mimic_framebuf_font import FONT_8X8

MONO_VLSB = 0
MVLSB = 0
RGB565 = 1
GS4_HMSB = 2
MONO_HLSB = 3
MONO_HMSB = 4
GS2_HMSB = 5
GS8 = 6


class FrameBuffer:
    def __init__(self, buffer, width, height, format, stride=-1):
        # modframebuf.c's framebuf_make_new_helper, including its size check:
        # a buffer too small for the geometry is a ValueError, not a crash later.
        if stride < 0:
            stride = width
        if width < 1 or height < 1 or width > 0xFFFF or height > 0xFFFF or stride > 0xFFFF or stride < width:
            raise ValueError("invalid geometry")
        bpp = 1
        height_required = height
        width_required = width
        strides_required = height - 1
        if format == MONO_VLSB:
            height_required = (height + 7) & ~7
            strides_required = height_required - 8
        elif format == MONO_HLSB or format == MONO_HMSB:
            stride = (stride + 7) & ~7
            width_required = (width + 7) & ~7
        elif format == GS2_HMSB:
            stride = (stride + 3) & ~3
            width_required = (width + 3) & ~3
            bpp = 2
        elif format == GS4_HMSB:
            stride = (stride + 1) & ~1
            width_required = (width + 1) & ~1
            bpp = 4
        elif format == GS8:
            bpp = 8
        elif format == RGB565:
            bpp = 16
        else:
            raise ValueError("invalid format")
        need = (strides_required * stride + (height_required - strides_required) * width_required) * bpp // 8
        if need > len(buffer):
            raise ValueError("buffer too small")
        self.buf = buffer
        self.width = width
        self.height = height
        self.format = format
        self.stride = stride

    # ---- one pixel, no clipping (callers clip) ------------------------------

    def _set(self, x, y, c):
        f = self.format
        b = self.buf
        if f == MONO_VLSB:
            i = (y >> 3) * self.stride + x
            bit = y & 7
            b[i] = (b[i] & ~(1 << bit)) | (int(c != 0) << bit)
        elif f == MONO_HLSB:
            i = (x + y * self.stride) >> 3
            bit = 7 - (x & 7)
            b[i] = (b[i] & ~(1 << bit)) | (int(c != 0) << bit)
        elif f == MONO_HMSB:
            i = (x + y * self.stride) >> 3
            bit = x & 7
            b[i] = (b[i] & ~(1 << bit)) | (int(c != 0) << bit)
        elif f == RGB565:
            i = (x + y * self.stride) * 2
            b[i] = c & 0xFF
            b[i + 1] = (c >> 8) & 0xFF
        elif f == GS2_HMSB:
            i = (x + y * self.stride) >> 2
            shift = (x & 3) << 1
            b[i] = (b[i] & ~(3 << shift)) | ((c & 3) << shift)
        elif f == GS4_HMSB:
            i = (x + y * self.stride) >> 1
            if x & 1:
                b[i] = (c & 0x0F) | (b[i] & 0xF0)
            else:
                b[i] = ((c & 0x0F) << 4) | (b[i] & 0x0F)
        else:
            b[x + y * self.stride] = c & 0xFF

    def _get(self, x, y):
        f = self.format
        b = self.buf
        if f == MONO_VLSB:
            return (b[(y >> 3) * self.stride + x] >> (y & 7)) & 1
        if f == MONO_HLSB:
            return (b[(x + y * self.stride) >> 3] >> (7 - (x & 7))) & 1
        if f == MONO_HMSB:
            return (b[(x + y * self.stride) >> 3] >> (x & 7)) & 1
        if f == RGB565:
            i = (x + y * self.stride) * 2
            return b[i] | (b[i + 1] << 8)
        if f == GS2_HMSB:
            return (b[(x + y * self.stride) >> 2] >> ((x & 3) << 1)) & 3
        if f == GS4_HMSB:
            if x & 1:
                return b[(x + y * self.stride) >> 1] & 0x0F
            return b[(x + y * self.stride) >> 1] >> 4
        return b[x + y * self.stride]

    def _setc(self, x, y, c):
        if 0 <= x and x < self.width and 0 <= y and y < self.height:
            self._set(x, y, c)

    # ---- the public surface ---------------------------------------------------

    def fill(self, c):
        self.fill_rect(0, 0, self.width, self.height, c)

    def pixel(self, x, y, c=None):
        # pixel(x, y) answers the colour, or None off the buffer;
        # pixel(x, y, c) sets it.
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            return None
        if c is None:
            return self._get(x, y)
        self._set(x, y, c)
        return None

    def fill_rect(self, x, y, w, h, c):
        if h < 1 or w < 1 or x + w <= 0 or y + h <= 0 or y >= self.height or x >= self.width:
            return
        xend = min(self.width, x + w)
        yend = min(self.height, y + h)
        x = max(x, 0)
        y = max(y, 0)
        yy = y
        while yy < yend:
            xx = x
            while xx < xend:
                self._set(xx, yy, c)
                xx = xx + 1
            yy = yy + 1

    def hline(self, x, y, w, c):
        self.fill_rect(x, y, w, 1, c)

    def vline(self, x, y, h, c):
        self.fill_rect(x, y, 1, h, c)

    def rect(self, x, y, w, h, c, f=False):
        if f:
            self.fill_rect(x, y, w, h, c)
        else:
            self.fill_rect(x, y, w, 1, c)
            self.fill_rect(x, y + h - 1, w, 1, c)
            self.fill_rect(x, y, 1, h, c)
            self.fill_rect(x + w - 1, y, 1, h, c)

    def line(self, x1, y1, x2, y2, c):
        # modframebuf.c's Bresenham, including its steep-swap and clipping.
        dx = x2 - x1
        sx = 1
        if dx <= 0:
            dx = -dx
            sx = -1
        dy = y2 - y1
        sy = 1
        if dy <= 0:
            dy = -dy
            sy = -1
        steep = False
        if dy > dx:
            x1, y1 = y1, x1
            dx, dy = dy, dx
            sx, sy = sy, sx
            steep = True
        e = 2 * dy - dx
        i = 0
        while i < dx:
            if steep:
                self._setc(y1, x1, c)
            else:
                self._setc(x1, y1, c)
            while e >= 0:
                y1 = y1 + sy
                e = e - 2 * dx
            x1 = x1 + sx
            e = e + 2 * dy
            i = i + 1
        self._setc(x2, y2, c)

    def scroll(self, xstep, ystep):
        if xstep < 0:
            sx = 0
            xend = self.width + xstep
            if xend <= 0:
                return
            dx = 1
        else:
            sx = self.width - 1
            xend = xstep - 1
            if xend >= sx:
                return
            dx = -1
        if ystep < 0:
            y = 0
            yend = self.height + ystep
            if yend <= 0:
                return
            dy = 1
        else:
            y = self.height - 1
            yend = ystep - 1
            if yend >= y:
                return
            dy = -1
        while y != yend:
            x = sx
            while x != xend:
                self._set(x, y, self._get(x - xstep, y - ystep))
                x = x + dx
            y = y + dy

    def blit(self, fbuf, x, y, key=-1, palette=None):
        if (x >= self.width or y >= self.height or -x >= fbuf.width
                or -y >= fbuf.height):
            return
        x0 = max(0, x)
        y0 = max(0, y)
        x1 = max(0, -x)
        y1 = max(0, -y)
        x0end = min(self.width, x + fbuf.width)
        y0end = min(self.height, y + fbuf.height)
        while y0 < y0end:
            cx1 = x1
            cx0 = x0
            while cx0 < x0end:
                col = fbuf._get(cx1, y1)
                if palette is not None:
                    col = palette._get(col, 0)
                if col != key:
                    self._set(cx0, y0, col)
                cx1 = cx1 + 1
                cx0 = cx0 + 1
            y1 = y1 + 1
            y0 = y0 + 1

    def text(self, s, x0, y0, c=1):
        # modframebuf.c's framebuf_text: one glyph per UTF-8 BYTE (so a
        # non-ASCII character draws as several glyph-127 boxes, as there),
        # 8 columns each, clipped per pixel.
        for chr in s.encode("utf-8"):
            if chr < 32 or chr > 127:
                chr = 127
            base = (chr - 32) * 8
            j = 0
            while j < 8:
                if 0 <= x0 and x0 < self.width:
                    col = FONT_8X8[base + j]
                    y = y0
                    while col:
                        if col & 1:
                            if 0 <= y and y < self.height:
                                self._set(x0, y, c)
                        col = col >> 1
                        y = y + 1
                j = j + 1
                x0 = x0 + 1
