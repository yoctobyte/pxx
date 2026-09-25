# SPDX-License-Identifier: 0BSD
# binascii, the subset MicroPython networking libraries import (umqtt.simple, mqtt_as).
# Expected output is CPython 3 byte for byte.
import binascii
from binascii import hexlify, unhexlify
print(hexlify(b"\x00\x1b\xff"))
print(hexlify(b"\xde\xad\xbe\xef", ":"))
print(hexlify(b""))
print(unhexlify("00ff1B"))
print(unhexlify(b"deadbeef"))
print(binascii.b2a_base64(b"pxx"))
print(binascii.b2a_base64(b"pxx", newline=False))
print(binascii.a2b_base64(b"cHh4"))
try:
    unhexlify("abc")
except ValueError as e:
    print("ValueError:", e)
try:
    unhexlify("zz")
except binascii.Error as e:
    print("Error:", e)
