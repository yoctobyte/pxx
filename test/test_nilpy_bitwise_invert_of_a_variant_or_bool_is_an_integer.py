# `~x` is `x ^ -1` for every int and bool. It used to compile as a LOGICAL
# not whenever the operand was not statically an integer: a variant
# parameter (a def called with two argument types) or a bool. The framebuf
# bit-set below read 0 for ~(1 << bit) and lost bits, and consuming the
# result another way segfaulted on a tag compare through address 0.
def setbit(b, y, c):
    i = y >> 3
    bit = y & 7
    b[i] = (b[i] & ~(1 << bit)) | (int(c != 0) << bit)

def via(b, y, c):
    setbit(b, y, c)

def inv(v):
    return ~v, ~(1 << v), ~(v + 0)

def inv2(v):
    return inv(v)

buf = bytearray(2)
setbit(buf, 1, 1)
via(buf, 2, "x")
via(buf, 9, 1)
setbit(buf, 1, 0)
print(buf[0], buf[1])
print(inv(2))
print(inv2(3))
t = True
f = False
print(~t, ~f, ~5, ~(-1), ~(5 > 1))
