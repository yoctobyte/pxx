# Keyword arguments and omitted defaults when a class is constructed as a VALUE:
# self.__class__(...) from the class and from a subclass, and a name bound to a class.
# bug-n-a-keyword-argument-through-a-class-value-is-refused-at-runtime
class P:
    def __init__(self, a, b=2, c="c"):
        self.a = a
        self.b = b
        self.c = c

    def kw(self):
        return self.__class__(self.a, b=99)

    def pos(self):
        return self.__class__(self.a)

    def kwonly(self):
        return self.__class__(c="z", a=self.a + 1)

    def show(self):
        return "%s %s %s %s" % (type(self).__name__, self.a, self.b, self.c)


class Q(P):
    pass


print(P(5).kw().show())
print(P(5).pos().show())
print(P(5).kwonly().show())
print(Q(7).kw().show())
k = Q
print(k(1, c=3).show())

kinds = {"p": P, "q": Q}
for name in ["p", "q"]:
    print(kinds[name](2, c="d").show())
for bad in [{"a": 3}, {"d": 3}]:
    try:
        if "a" in bad:
            kinds["q"](1, a=3)
        else:
            kinds["q"](1, d=3)
    except TypeError:
        print("TypeError", list(bad)[0])
