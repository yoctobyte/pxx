# -x, +x, abs(x), ~x on a user object call __neg__/__pos__/__abs__/__invert__
# whether the operand is statically a class or a VARIANT (a mixed list element).
# +x was a no-op, a variant ~x/abs/-x raised or printed a large integer, and
# `-+v` did not parse. Expected = python3.
# bug-n-unary-dunders-do-not-dispatch-on-a-variant-operand
class V:
    def __init__(self, x=0.0):
        self.x = float(x)
    def __neg__(self): return V(-self.x)
    def __pos__(self): return V(self.x + 100)
    def __abs__(self): return V(abs(self.x) * 10)
    def __invert__(self): return V(-self.x - 1)
class N:
    pass
def u(a):
    return (-a).x, (+a).x, abs(a).x, (~a).x
print(u(V(2.0)))
v = V(3)
print((+v).x, (-+v).x, (+-v).x, +5, -+5, +2.5)
try:
    print(+N())
except TypeError:
    print("TypeError")
class W:
    def __init__(self, x=0.0):
        self.x = float(x)
    def __neg__(self): return W(-self.x)
    def __pos__(self): return W(self.x + 100)
    def __abs__(self): return W(abs(self.x) * 10)
    def __invert__(self): return W(-self.x - 1)
    def __repr__(self): return "W(%s)" % self.x
xs = [W(1), 2.5, 3]
for e in xs:
    print(-e, +e, abs(e))
print(~xs[0], ~xs[2])
ys = [True, 7, 2.5, -0.0]
for e in ys:
    print(+e, -e)
class M:
    pass
zs = [M(), 1]
try:
    print(-zs[0])
except TypeError as ex:
    print("TypeError", ex)
try:
    print(+zs[0])
except TypeError as ex:
    print("TypeError", ex)
