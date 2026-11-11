# Keyword arguments to a generator, in value position and as a for-loop's
# iterable. bug-nilpy-a-keyword-argument-to-a-generator-does-not-compile
acc = [100]


def g(n, xs=None, d=acc):
    yield n
    yield xs
    yield d[0]


def h(a, b=2, *, c=3):
    yield a + b + c


print(list(g(1, xs=7)))
print(list(g(1, d=[5])))
print(list(g(n=2, xs="s")))
print(list(g(1)))
print(list(h(1, c=10)))
print(list(h(1, b=5)))
for v in g(3, xs=4):
    print(v)
