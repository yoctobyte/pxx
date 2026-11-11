# A plain function (or lambda) bound in a CLASS BODY is a method when read off
# an instance: `c.plain(7)` calls `two(c, 7)`. staticmethod() opts out, an
# instance attribute set in a method never binds, and the class door passes
# everything explicitly. bug-n-a-plain-function-as-a-class-attribute-does-not-bind-the-receiver


def two(a, b):
    return "a=" + type(a).__name__ + " b=" + str(b)


def one(a):
    return "one " + str(a)


class C:
    plain = two
    stat = staticmethod(one)
    lam = lambda self, x: x * 10

    def __init__(self):
        self.cb = one

    def inside(self):
        return self.plain(3)


class D(C):
    pass


class E(C):
    plain = staticmethod(one)


c = C()
print(C.plain(1, 7))
print(c.plain(7))
print(c.inside())
print(c.stat(5))
print(c.lam(4))
print(c.cb(6))
d = D()
print(d.plain(8), d.inside())
e = E()
print(e.plain(9))
z = complex(3, 4)
print(abs(z))


# ---- a subclass with an INHERITED __init__ rebinding class attributes: its
# own level is stored after construction, and __init__'s self.<name> wins
class C2:
    k = 1
    tag = "c"
    def __init__(self):
        self.tag = "init"
        self.n = 5
class E2(C2):
    k = 2
    tag = "e"
class F2(E2):
    pass
class G2(C2):
    k = 3
    def __init__(self):
        super().__init__()
        self.extra = self.k * 10
for o in [C2(), E2(), F2(), G2()]:
    print(type(o).__name__, o.k, o.tag, o.n)
print(G2().extra, E2.k, F2.k)
