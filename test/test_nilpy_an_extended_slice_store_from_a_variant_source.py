# An extended-slice store whose SOURCE is a variant (a dict value, a call
# chain) into a statically typed bytearray/list: refused at compile time, and
# that refusal stopped lekkerzeilen building on latest (app.py's cover texture).
# bug-n-an-extended-slice-store-from-a-variant-source-is-refused
import sys
d = {"b": b"\x01\x02\x03\x04", "l": [9, 8]}
pixels = bytearray(8)
lo = 0 if sys.byteorder == "little" else 1
pixels[0::2] = d["b"]
print(list(pixels))
src = bytes([5, 0, 6, 0, 7, 0, 8, 0])
pixels[1::2] = src[lo::2].translate(bytes(range(256)))
print(list(pixels))
xs = [0, 0, 0, 0]
xs[::2] = d["l"]
print(xs)
