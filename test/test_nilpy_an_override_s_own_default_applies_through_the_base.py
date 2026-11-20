# An omitted argument takes the default of the method that RUNS, not of the
# static callee: CPython evaluates the override's own default.
# bug-n-an-overrides-own-default-is-ignored-when-dispatched-through-the-base


class F:
    def m(self, a, b=1):
        return "F " + str(a + b)

    def uses(self):
        return self.m(10)

    def tag(self, s="f"):
        return "F:" + s

    def say(self):
        return self.tag()


class G(F):
    def m(self, a, b=2):
        return "G " + str(a * b)

    def tag(self, s="g"):
        return "G:" + s


class H(G):
    # same default as its parent: still the nearest override's default
    def m(self, a, b=2):
        return "H " + str(a - b)


class K(G):
    # inherits G.m and G.tag outright
    pass


class Same(F):
    # overrides with the SAME default as the base: the plain path
    def m(self, a, b=1):
        return "S " + str(a * 100 + b)


for o in [F(), G(), H(), K(), Same()]:
    print(o.uses(), o.say())

x = G()
print(x.m(3), x.m(3, 5))
f = F()
print(f.m(3))
