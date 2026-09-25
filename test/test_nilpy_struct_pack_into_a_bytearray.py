# SPDX-License-Identifier: 0BSD
# struct.pack_into, as umqtt.simple uses it; expected is CPython 3.
import struct
b = bytearray(8)
struct.pack_into("!H", b, 2, 0x1234)
print(b)
struct.pack_into("<HI", b, 0, 1, 0xdeadbeef)
print(b)
struct.pack_into(">B", b, -1, 7)
print(b)
vals = [1, 2, 3, 4, 5]
struct.pack_into("5B", b, 3, *vals)
print(b)
for off in (7, -9, -1):
    try:
        struct.pack_into("!H", b, off, 1)
    except struct.error as e:
        print("error:", e)
