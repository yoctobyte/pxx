# hasattr on a list, tuple, set and frozenset answers each type's own surface.
# All four are one class (TPyList), so it answered the union for every one:
# hasattr([1], "add") and hasattr((1,), "append") were True. Literal and
# computed names, static and variant receivers, a list subclass. Expected = python3.
# bug-n-a-list-and-a-set-share-one-class-so-introspection-cannot-tell-them-apart
a = [1]
s = {1, 2}
t = (1, 2)
print(isinstance(a, set), isinstance(s, list), isinstance(t, list), isinstance(a, list), isinstance(s, set), isinstance(t, tuple))
def h(x, n):
    return hasattr(x, n)
for n in ("add", "update", "append", "sort", "count", "index", "union", "discard", "extend"):
    print(n, hasattr(a, n), hasattr(s, n), hasattr(t, n), h(a, n), h(s, n), h(t, n))
a = [1]
s = {1, 2}
t = (1, 2)
fz = frozenset([1])
print(hasattr(a, "add"), hasattr(a, "append"), hasattr(s, "update"), hasattr(s, "append"), hasattr(t, "count"), hasattr(t, "append"))
print(hasattr(fz, "add"), hasattr(fz, "union"), hasattr(a, "__len__"), hasattr(s, "__contains__"), hasattr(a, "nope"))
def g(x):
    return hasattr(x, "add"), hasattr(x, "sort"), hasattr(x, "upper")
print(g(a), g(s), g(t), g("str"), g(3))
class L(list):
    def add(self, v):
        self.append(v)
l = L()
print(hasattr(l, "append"), hasattr(l, "add"))
w = 6
for n in ("__contains__", "__iter__", "__len__", "__getitem__", "__setitem__", "__add__", "__and__", "__ior__", "__reversed__"):
    print(n, hasattr(a, n), hasattr(s, n), hasattr(t, n), hasattr(fz, n))
