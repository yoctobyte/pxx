# Run under BOTH pxx and CPython; the two outputs must be byte-identical.
#
# WHAT THIS GUARDS, AND WHY NO OTHER FIXTURE IN THE TREE CAN.  Every lib/rtl
# unit that carries a Python surface beside its Pascal one has to hand back the
# TYPE CPython hands back, not just the same bytes.  base64.b64encode returned
# AnsiString where CPython returns bytes for months: the characters were
# identical, so every value comparison, every round trip through the module and
# every print agreed with the oracle, and the first program to write the
# idiomatic `b64encode(x).decode()` got an AttributeError.
#
# SO EVERY ROW HERE PRINTS A repr() OR A type(), NEVER A BARE VALUE.  A row that
# prints the value is a row this file cannot fail on, and adding one is the way
# to quietly retire the guard.
#
# AND NOTHING HERE MAY PRINT DEFLATE OUTPUT.  Which matches an encoder finds is
# latitude -- pxx and CPython both compress well and emit different bytes -- so
# a row printing `zlib.compress(x)` or its length would be red for no defect.
# The compressed half is asserted the only way that is actually a claim: a
# stream CPython produced, frozen below, must decompress to the known plaintext,
# and our own output must survive our own round trip.
import base64
import zlib

raw = b"hello from pxx"

# ---- base64: the type is the assertion -------------------------------------
e = base64.b64encode(raw)
print("b64encode      ", repr(e), type(e).__name__)
print("b64encode.decode", repr(e.decode()))
print("b64 concat     ", repr(b"Basic " + e))
d = base64.b64decode("aGVsbG8gZnJvbSBweHg=")
print("b64decode str  ", repr(d), type(d).__name__)
# The round trip through BYTES, which is the row that found b64decode's bytes
# arm returning empty -- a str argument had always worked, and nothing in the
# tree produced bytes to hand it until b64encode started returning them.
print("b64 roundtrip  ", repr(base64.b64decode(base64.b64encode(raw)) == raw))
print("b64 empty      ", repr(base64.b64encode(b"")), repr(base64.b64decode("")))
# Padding: one, two and no pad bytes, because the tail is where an encoder
# disagrees with itself.
print("b64 pad1       ", repr(base64.b64encode(b"ab")))
print("b64 pad2       ", repr(base64.b64encode(b"a")))
print("b64 pad0       ", repr(base64.b64encode(b"abc")))
# Non-ASCII, so the byte path cannot pass by being a text path that happens to
# work: 0x00 and 0xff survive only if the bytes are carried as bytes.
print("b64 binary     ", repr(base64.b64encode(bytes([0, 127, 128, 255]))))
print("b64 binary rt  ", repr(base64.b64decode(base64.b64encode(bytes([0, 127, 128, 255])))))

# ---- zlib: types, checksums, and a frozen CPython stream -------------------
c = zlib.compress(raw)
print("compress type  ", type(c).__name__)
print("decompress type", type(zlib.decompress(c)).__name__)
print("zlib roundtrip ", repr(zlib.decompress(zlib.compress(raw)) == raw))

plain = b"pxx lib/rtl python surface: the repr is the assertion, not the value"
frozen = (b"x\xda\x1d\xc8\xd1\t\xc00\x08\x05\xc0U\xde\x00\x85\xfew\x1b[\x0c\x11D"
          b"\x83\x9a\x92n_\xc8\xdfqc-\xa8\xdcg\x94b|\xd5\xdd\x903\x1a=|\xa1:#x\x04"
          b"$\xb7)\x93\xa3\xc4\xed\x80y\xedzI'\xffd\xbe\x19\x08")
print("frozen stream  ", repr(zlib.decompress(frozen) == plain))
print("frozen repr    ", repr(zlib.decompress(frozen)[:16]))

# THE SEEDED ROWS ARE THE POINT OF THE UNSEEDED ONES.  crc32's CPython default
# is 0, which is exactly the value an omitted argument already reads as here, so
# the one-argument row agrees with the oracle even when the absence handling is
# broken.  The two-argument rows are the ones that can fail.
print("crc32          ", repr(zlib.crc32(plain)))
print("crc32 seeded   ", repr(zlib.crc32(plain, 12345)))
print("adler32        ", repr(zlib.adler32(plain)))
print("adler32 seeded ", repr(zlib.adler32(plain, 7)))
# Chunked continuation: correct for a one-shot caller and wrong for a chunked
# one is a real failure mode of both checksums, and only this row sees it.
print("crc32 chunked  ", repr(zlib.crc32(plain[20:], zlib.crc32(plain[:20])) == zlib.crc32(plain)))
print("adler32 chunked", repr(zlib.adler32(plain[20:], zlib.adler32(plain[:20])) == zlib.adler32(plain)))
