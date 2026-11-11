# Every row of feature-nilpy-small-syntax-gaps-found-by-the-2026-08-06-sweep,
# each refused or wrong when the sweep was taken, all matching CPython now.
a, b, c = 1, 2, 3
print("{} {} {}".format(a, b, c))
print(list(enumerate("ab")))
print(type(1) == int, type("a") == str, type(1) is int)
f = lambda x, y=1: x + y
print(f(2), f(2, 5))
print("a", "b", sep="-")
d = dict(x=1, y=2)
print(d)
d.update(b=2)
d.update(c=3, e=4)
print(d)
cs = [1, 2, 3, 4]
cs[::2] = [7, 8]
print(cs)
class Base:
    def name(self):
        return self.__class__.__name__
class Kid(Base):
    pass
print(Base().name(), Kid().name())
(cc, dd), e = (3, 4), 5
print(cc, dd, e)
t = 1, 2, 3
print(t)
print([(i, j) for i in range(2) for j in range(2)])
