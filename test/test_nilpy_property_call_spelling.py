# `name = property(getter[, setter[, deleter[, doc]]])` in a class body is the
# same property @property makes; it was `undefined variable (property)`.
# The accessors are bound when the line runs, so a subclass overriding the
# getter does not change what the property reads (CPython: A.getV for B().v).
# bug-n-property-works-as-a-decorator-but-is-not-a-builtin-name
class Node:
    def __init__(self, name):
        self._name = name
        self._kids = []

    def _get_name(self):
        return self._name

    def _set_name(self, v):
        self._name = v.upper()

    def _get_count(self):
        return len(self._kids)

    name = property(_get_name, _set_name)
    count = property(_get_count)

    def add(self, k):
        self._kids.append(k)
        return self.count


class Sub(Node):
    def describe(self):
        return self.name + ":" + str(self.count)


n = Node("a")
print(n.name)
n.name = "bee"
print(n.name)
print(n.add(1), n.add(2))
print(n.count)
s = Sub("x")
s.add(3)
print(s.describe())
s.name = "why"
print(s.describe())


class PA:
    def __init__(self):
        self._v = [1, 2]

    def getV(self):
        return self._v

    v = property(getV, None, None, "the v")


class PB(PA):
    def getV(self):
        return [9]


print(PA().v, PB().v, len(PB().v))


class C:
    def _g(self):
        return self._x
    def _s(self, n):
        self._x = n
    v = property(_g, _s)

c = C()
c.v = 7
print(c.v)
