# A base-class method calling a method only a SUBCLASS defines -- the
# template-method shape micropython-lib's display drivers are written in.
# Python resolves the name on the runtime class, and a bare base instance is
# AttributeError at run time. It used to be refused at compile time
# ("Base has no method scale"). Each subclass keeps its own typed ABI; a
# deeper override is still reached; arguments are evaluated once.
log = []
def tick(v):
    log.append(v)
    return v
class Base:
    def twice(self, x):
        return self.scale(x) * 2
    def label(self):
        return "<" + self.name() + ">"
    def total(self, xs):
        return self.sumup(xs) + 1
    def fire(self):
        self.hook(tick(5))
        return len(log)
    def go(self):
        self.hook(0)
    def both(self):
        return self.base + self.extra
class A(Base):
    def __init__(self):
        self.base = 1
        self.extra = 2
    def scale(self, x: int) -> int:
        return x + 1
    def name(self):
        return "a"
    def sumup(self, xs):
        return sum(xs)
    def hook(self, v):
        log.append("A" + str(v))
class AA(A):
    def scale(self, x: int) -> int:
        return x * 100
class B(Base):
    def scale(self, x):
        return x - 1.5
    def name(self):
        return "bee"
print(A().twice(4), AA().twice(4), B().twice(4))
print(A().label(), B().label())
print(A().total([1, 2, 3]), A().both())
print(A().fire(), log)
A().go()
print(log)
for f in (lambda: Base().twice(1), lambda: Base().go()):
    try:
        f()
    except AttributeError as e:
        print("AttributeError", e)
