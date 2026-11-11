# A nested def taken as a value carries its captures at any arity up to 8, and
# a str capture travels too. Both used to read 0 (or an empty list) silently.
# bug-n-a-returned-nested-def-reads-zero-for-its-captures-past-arity-three


def a0():
    n = 42
    def b():
        return n
    return b


def a1():
    n = 42
    def b(x):
        return n
    return b


def a3():
    n = 42
    def b(x, y, z):
        return n
    return b


def a4():
    n = 42
    def b(x, y, z, w):
        return n + w - 4
    return b


def a5(i, o):
    def step(a, b, c, e, f):
        return "i=%s o=%s sum=%s" % (i, o, a + f)
    return step


def a8(k):
    def step(a, b, c, d, e, f, g, h):
        return k + a + b + c + d + e + f + g + h
    return step


def inside():
    n = 42
    def b(x, y, z, w):
        return n + x
    return b(1, 2, 3, 4)


def s1():
    s = "forty-two"
    def b(x):
        return s
    return b


def s4(tail):
    s = "forty-two"
    def b(x, y, z, w):
        return s + tail + str(w)
    return b


def l4():
    xs = [4, 2]
    def b(x, y, z, w):
        return xs
    return b


def lam4(i, o):
    return lambda a, b, c, e: "i=%s o=%s" % (i, o)


class Holder:
    tag = "T"

    def make4_self(self, i, o):
        def step(a, b, c, e):
            return "i=%s o=%s tag=%s" % (i, o, self.tag)
        return step


print("a0", a0()())
print("a1", a1()(1))
print("a3", a3()(1, 2, 3))
print("a4", a4()(1, 2, 3, 4))
print("a5", a5(False, 7)(1, 2, 3, 4, 5))
print("a8", a8(100)(1, 2, 3, 4, 5, 6, 7, 8))
print("inside", inside())
print("s1", s1()(1))
print("s4", s4("!")(1, 2, 3, 4))
print("l4", l4()(1, 2, 3, 4))
print("lam4", lam4(False, 7)(1, 2, 3, 4))
print("self4", Holder().make4_self(1, 2)(1, 2, 3, 4))
fs = [s4(str(i)) for i in range(3)]
print("many", [f(0, 0, 0, i) for i, f in enumerate(fs)])
