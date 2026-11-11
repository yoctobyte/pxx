# A method's receiver is its first parameter, whatever it is called.
# bug-n-a-method-receiver-parameter-must-be-literally-named-self-or-every-argument-shifts
def kw(zz=0, s=0):
    return zz * 10 + s

def helper():
    return 7

class K:
    def __init__(zz, v):
        zz.x = v
        zz.zz = v + 1            # an attribute spelled like the receiver
    def get(this):
        return this.x
    def both(s, a, b=2):
        return s.x + a + b + kw(zz=1, s=2)   # keyword labels stay labels
    @property
    def doubled(me):
        return me.x * 2
    @staticmethod
    def twice(v):
        return v * 2
    @classmethod
    def make(kls, v):
        return kls(v * 2)
    def one(o): return o.x + 100

class W:
    def __init__(zz):
        zz.g = helper
    def run(zz):
        return zz.g()

def f(a, b):
    return (a, b)

class S:
    __slots__ = ("g",)
    def __init__(s, v):
        s.g = v

k = K(5)
print(k.get(), K(6).get())
print(k.zz)
print(k.both(1), k.both(1, b=3))
print(k.doubled)
print(K.twice(4), K.make(3).get())
print(k.one())
print(W().run())
ks = [S(f)]
print(ks[0].g(1, 2))
