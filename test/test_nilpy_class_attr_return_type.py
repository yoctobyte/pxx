# A def returning a class attribute read through the class NAME (`C.k`) had
# its return type inferred as the class itself: floats came back as raw bits,
# str/list as pointers, None as 0 on x86-64, and 32-bit targets refused the
# write. Every shape here must print what CPython prints.

class A:
    f = 2.5
    s = "hi"
    xs = [1, 2, 3]
    n = None
    i = 7
    def mf(self):
        return A.f
    def ms(self):
        return A.s
    def mxs(self):
        return A.xs
    def mn(self):
        return A.n
    def mi(self):
        return A.i
    def lf(self):
        v = A.f
        return v
    def ls(self):
        v = A.s
        return v
    def dun(self):
        return self.__class__.f
    @classmethod
    def cf(cls):
        return cls.s

def pf():
    return A.f
def ps():
    return A.s
def pxs():
    return A.xs
def pn():
    return A.n

a = A()
print(a.mf(), a.ms(), a.mxs(), a.mn(), a.mi())
print(a.lf(), a.ls(), a.dun(), A.cf())
print(pf(), ps(), pxs(), pn())
x = pf()
print(x * 2.0)

class B:
    k = 2.5
class D(B):
    pass
class E(B):
    k = "sub"
def inh():
    return D.k
def red1():
    return B.k
def red2():
    return E.k
print(inh(), red1(), red2())

class W:
    k = 1.5
def bump():
    W.k = W.k + 1.0
def wget():
    return W.k
bump()
print(wget())

class K:
    b = True
    d = {"a": 1}
    t = (1, 2)
    s = "ab"
def kb():
    return K.b
def kd():
    return K.d
def kt():
    return K.t
def kup():
    return K.s.upper()
def kidx():
    return K.t[1]
print(kb(), kd(), kt(), kd()["a"], kup(), kidx())

class P:
    def __init__(self):
        self.v = 9
    def hi(self):
        return 3
class H:
    p = P()
    ref = P
def hp():
    return H.p
def href():
    return H.ref
print(hp().v, href()().hi())
