# pick().m(*xs): a star-unpack into a method reached through a call chain.
# feature-n-a-call-cannot-unpack-a-sequence-into-its-arguments
class K:
    def __init__(self, base=0):
        self.base = base
    def m(self, a, b):
        return self.base + a + b
    def v(self, *xs):
        return self.base + sum(xs)
    def me(self):
        return self
def pick():
    return K(10)
ys = [3, 4]
print(pick().m(*ys))
r = pick().m(*ys)
print(r)
print(pick().v(*ys), pick().v(1, *ys))
print(pick().me().m(*ys))
print([K(1)][0].m(*ys))
print(K(2).me().v(*[5, 6, 7]))
def q():
    return pick().m(*(1, 2))
print(q())
