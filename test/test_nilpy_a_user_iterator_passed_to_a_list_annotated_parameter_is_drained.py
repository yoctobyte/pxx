# A user object implementing __iter__, passed to a def whose parameter is
# annotated `list`, arrives as the list CPython's iteration would give. The
# annotation is not enforced in CPython; pxx used to read the object through
# TPyList's layout and crash. A duck-typed argument to a class-annotated
# parameter must still be accepted.
# The callee here only iterates once: that is where draining agrees with
# CPython (len() or a second pass over a one-shot iterator would not).
# bug-n-pyfixiterableargs-is-inert-its-own-test-passes-with-it-disabled

class Counter:
    def __init__(self, n):
        self.n = n
        self.i = 0
    def __iter__(self):
        return self
    def __next__(self):
        if self.i >= self.n:
            raise StopIteration
        self.i += 1
        return self.i

class Bag:
    def __init__(self, items):
        self.items = items
    def __iter__(self):
        return iter(self.items)

def total(xs: list) -> int:
    s = 0
    for x in xs:
        s += x
    return s

def joined(xs: list[str]) -> str:
    out = ""
    for x in xs:
        out += x
    return out

print(total(Counter(4)))
c = Counter(3)
print(total(c))
print(total(Bag([4, 5, 6])), total([7, 8]))
b = Bag(["x", "y"])
print(joined(b), joined(b), joined(["p", "q"]))

class A:
    def __init__(self):
        self.x = 1
class C:
    def __init__(self):
        self.x = 3

def f(p: A) -> int:
    return p.x

print(f(A()), f(C()))
