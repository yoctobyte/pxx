#!/usr/bin/env python3
"""Wrap a relocation-free COFF object's .text into a minimal x64 PE DLL that
exports its external functions. Test scaffolding for test-windows: there is
no PE linker on the build host, and a callee written in C (compiled with
`clang --target=x86_64-pc-windows-msvc -c`) is what checks the Microsoft
x64 record rules from the other side.
usage: mkdll.py OBJ OUT.dll DLLNAME"""
import struct, sys

obj, out, dllname = sys.argv[1], sys.argv[2], sys.argv[3]
d = open(obj, 'rb').read()
nsec, = struct.unpack_from('<H', d, 2)
symptr, nsym = struct.unpack_from('<II', d, 8)
opthdr, = struct.unpack_from('<H', d, 16)
secs = []
for i in range(nsec):
    o = 20 + opthdr + 40 * i
    name = d[o:o + 8].rstrip(b'\0')
    size, raw, nrel = struct.unpack_from('<I', d, o + 16)[0], struct.unpack_from('<I', d, o + 20)[0], struct.unpack_from('<H', d, o + 32)[0]
    secs.append((name, size, raw, nrel))
text = [s for s in secs if s[0] == b'.text'][0]
assert text[3] == 0, 'text has relocations'
code = d[text[2]:text[2] + text[1]]
strtab = symptr + 18 * nsym
syms = []
i = 0
while i < nsym:
    o = symptr + 18 * i
    nm = d[o:o + 8]
    if nm[:4] == b'\0\0\0\0':
        off, = struct.unpack_from('<I', nm, 4)
        nm = d[strtab + off:d.index(b'\0', strtab + off)]
    else:
        nm = nm.rstrip(b'\0')
    val, = struct.unpack_from('<I', d, o + 8)
    secn, = struct.unpack_from('<h', d, o + 12)
    typ, = struct.unpack_from('<H', d, o + 14)
    scl = d[o + 16]
    naux = d[o + 17]
    if scl == 2 and secn == 1 and typ == 0x20:
        syms.append((nm, val))
    i += 1 + naux
syms.sort()

TEXT_RVA, EDATA_RVA = 0x1000, 0x2000
# export directory
names = [n for n, _ in syms]
nfun = len(syms)
ed = bytearray(40)
eat_off = 40
npt_off = eat_off + 4 * nfun
ord_off = npt_off + 4 * nfun
str_off = ord_off + 2 * nfun
strs = bytearray(dllname.encode() + b'\0')
name_rvas = []
for n in names:
    name_rvas.append(EDATA_RVA + str_off + len(strs))
    strs += n + b'\0'
struct.pack_into('<IIHHIIIIIII', ed, 0, 0, 0, 0, 0, EDATA_RVA + str_off, 1, nfun, nfun,
                 EDATA_RVA + eat_off, EDATA_RVA + npt_off, EDATA_RVA + ord_off)
for n, v in syms:
    ed += struct.pack('<I', TEXT_RVA + v)
for r in name_rvas:
    ed += struct.pack('<I', r)
for k in range(nfun):
    ed += struct.pack('<H', k)
ed += strs

def pad(b, n):
    return bytes(b) + b'\0' * ((-len(b)) % n)

hdr = bytearray(0x400)
hdr[0:2] = b'MZ'
struct.pack_into('<I', hdr, 0x3c, 0x80)
p = 0x80
hdr[p:p + 4] = b'PE\0\0'
struct.pack_into('<HHIIIHH', hdr, p + 4, 0x8664, 2, 0, 0, 0, 240, 0x2022)
o = p + 24
struct.pack_into('<HBBIIIII', hdr, o, 0x20b, 14, 0, 0x200, 0x200, 0, 0, TEXT_RVA)
struct.pack_into('<Q', hdr, o + 24, 0x10000000)
struct.pack_into('<IIHHHHHHIIIIHH', hdr, o + 32, 0x1000, 0x200, 6, 0, 0, 0, 6, 0, 0, 0x3000, 0x400, 0, 3, 0x0100)
struct.pack_into('<QQQQII', hdr, o + 72, 0x100000, 0x1000, 0x100000, 0x1000, 0, 16)
struct.pack_into('<II', hdr, o + 112, EDATA_RVA, len(ed))
s = o + 240
hdr[s:s + 8] = b'.text\0\0\0'
struct.pack_into('<IIIIIIHHI', hdr, s + 8, len(code), TEXT_RVA, len(pad(code, 0x200)), 0x400, 0, 0, 0, 0, 0x60000020)
s += 40
hdr[s:s + 8] = b'.edata\0\0'
struct.pack_into('<IIIIIIHHI', hdr, s + 8, len(ed), EDATA_RVA, len(pad(ed, 0x200)), 0x400 + len(pad(code, 0x200)), 0, 0, 0, 0, 0x40000040)
open(out, 'wb').write(bytes(hdr) + pad(code, 0x200) + pad(ed, 0x200))
print('exports', [n.decode() for n in names])
