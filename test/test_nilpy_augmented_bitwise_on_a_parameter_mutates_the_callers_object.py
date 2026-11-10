# `p &= x` (and |= ^= <<= >>=) on an UNANNOTATED PARAMETER must call the
# in-place dunder, so the CALLER sees the mutation -- CPython semantics. It
# called the plain dunder and rebound the local, a wrong value with no
# diagnostic. Expected = python3.
# bug-n-augmented-assignment-to-an-unannotated-parameter-silently-loses-the-mutation
class V:
    def __init__(self, x): self.x = x
    def __iand__(self, o):
        self.x = self.x & o.x
        return self
    def __and__(self, o):
        return V(self.x & o.x)
    def __ior__(self, o):
        self.x = self.x | o.x
        return self
    def __or__(self, o):
        return V(self.x | o.x)
    def __ixor__(self, o):
        self.x = self.x ^ o.x
        return self
    def __xor__(self, o):
        return V(self.x ^ o.x)
    def __ilshift__(self, o):
        self.x = self.x << o.x
        return self
    def __lshift__(self, o):
        return V(self.x << o.x)
    def __irshift__(self, o):
        self.x = self.x >> o.x
        return self
    def __rshift__(self, o):
        return V(self.x >> o.x)

def fa(p): p &= V(6)
def fo(p): p |= V(8)
def fx(p): p ^= V(3)
def fl(p): p <<= V(2)
def fr(p): p >>= V(1)
a = V(12); fa(a); print(a.x)
a = V(12); fo(a); print(a.x)
a = V(12); fx(a); print(a.x)
a = V(12); fl(a); print(a.x)
a = V(12); fr(a); print(a.x)
def g(c):
    print((c & V(6)).x, (c | V(1)).x, (c ^ V(5)).x, (c << V(1)).x, (c >> V(2)).x)
g(V(12))
