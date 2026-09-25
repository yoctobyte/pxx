# Bitwise and shift operators with a VARIANT operand, diffed against CPython.
# Driver code is register masks and shifts, so every int row must stay exact
# (a shift past 2^63, an arithmetic >>), and an object or a set held in a
# variant must reach its dunder / in-place update: `<<` `>>` on an object
# raised RunError 219, `&= |= <<=` never called __iand__/__ior__/__ilshift__,
# `s |= t` on a variant set came back empty, and `12 & c` with a class on
# the right only SIGSEGVed. set.add answers None, as in CPython.
# bug-n-a-bitwise-or-shift-operator-on-a-variant-user-object-never-reaches-its-dunder
class C:
    def __init__(self, v):
        self.v = v
    def __lshift__(self, o):
        return C(self.v << o)
    def __rshift__(self, o):
        return C(self.v >> o)
    def __and__(self, o):
        return C(self.v & o)
    def __rand__(self, o):
        return C(o & self.v)
    def __ror__(self, o):
        return C(o | self.v)
    def __rlshift__(self, o):
        return C(o << self.v)
    def __iand__(self, o):
        self.v = self.v & o
        return self
    def __ior__(self, o):
        self.v = self.v | o
        return self
    def __ilshift__(self, o):
        self.v = self.v << o
        return self
def var(x):
    return [x][0]
def t_shl_vi():
    a = var(5)
    print(a << 3)
t_shl_vi()
def t_shr_vi():
    a = var(-40)
    print(a >> 2)
t_shr_vi()
def t_shl_iv():
    b = var(4)
    print(3 << b)
t_shl_iv()
def t_shr_iv():
    b = var(1)
    print(1000 >> b)
t_shr_iv()
def t_shl_vv():
    a = var(7)
    b = var(2)
    print(a << b, a >> b)
t_shl_vv()
def t_shl_big():
    a = var(1)
    print(a << 70)
t_shl_big()
def t_and_iv():
    c = var(0x3C)
    print(12 & c, 12 | c, 12 ^ c)
t_and_iv()
def t_aug_and():
    r = var(0xFF)
    r &= 0x0F
    print(r)
t_aug_and()
def t_aug_or():
    r = var(0x10)
    r |= 0x01
    print(r)
t_aug_or()
def t_aug_xor():
    r = var(0x11)
    r ^= 0x01
    print(r)
t_aug_xor()
def t_aug_shl():
    r = var(3)
    r <<= 4
    print(r)
t_aug_shl()
def t_aug_shr():
    r = var(0x80)
    r >>= 3
    print(r)
t_aug_shr()
def t_aug_vv():
    r = var(0xF0)
    m = var(0x3C)
    r &= m
    r |= var(1)
    r <<= var(2)
    print(r)
t_aug_vv()
def t_aug_loop():
    regs = [0x00, 0x81, 0xFF]
    acc = 0
    for x in regs:
        acc |= x
        acc <<= 1
        acc &= 0xFFF
    print(acc)
t_aug_loop()
def t_mask():
    def rd(buf, i):
        return (buf[i] << 8) | buf[i + 1]
    print(rd([0x12, 0x34, 0x56], 1))
t_mask()
def t_obj_shl():
    c = var(C(20))
    print((c << 2).v, (c >> 1).v)
t_obj_shl()
def t_obj_rand():
    c = C(10)
    print((12 & c).v, (1 | c).v)
t_obj_rand()
def t_obj_rand_v():
    c = var(C(10))
    print((12 & c).v)
t_obj_rand_v()
def t_obj_rlsh():
    c = var(C(3))
    print((1 << c).v)
t_obj_rlsh()
def t_obj_iand():
    c = var(C(0xFF))
    c &= 0x0F
    print(c.v)
t_obj_iand()
def t_obj_ior():
    c = var(C(0x10))
    c |= 1
    print(c.v)
t_obj_ior()
def t_obj_ilsh():
    c = var(C(1))
    c <<= 5
    print(c.v)
t_obj_ilsh()
def t_set_ior():
    s = var({1, 2})
    s |= {3}
    print(sorted(s))
t_set_ior()
def t_set_iand():
    s = var({1, 2, 3})
    s &= {2, 3, 4}
    print(sorted(s))
t_set_iand()
def t_set_alias():
    s = {1}
    t = s
    t |= {2}
    print(sorted(s))
t_set_alias()
def t_setadd():
    s = set()
    r = s.add(1)
    print(r, r is None, len(s))
t_setadd()
class MM:
    def __init__(self, v):
        self.v = v
    def __matmul__(self, o):
        return self.v * 10 + o
    def __rmatmul__(self, o):
        return o * 100 + self.v
class IM:
    def __init__(self, v):
        self.v = v
    def __imatmul__(self, o):
        self.v = self.v + o
        return self
class HM:
    def __init__(self):
        self.o = [MM(1)][0]
def t_matmul():
    c = [MM(2)]
    x = c[0]
    print(x @ 3)
    print(5 @ c[0])
    xs = [7]
    v = xs[0]
    print(v @ MM(3))
t_matmul()
def t_matmul_typeerror():
    xs = [7, "s"]
    try:
        print(xs[0] @ xs[1])
    except TypeError:
        print("TypeError")
t_matmul_typeerror()
def t_imatmul():
    c = [MM(2)]
    x = c[0]
    x @= 4
    print(x)
    d = [IM(5)]
    y = d[0]
    y @= 6
    print(y.v)
    k = HM()
    k.o @= 9
    print(k.o)
t_imatmul()
