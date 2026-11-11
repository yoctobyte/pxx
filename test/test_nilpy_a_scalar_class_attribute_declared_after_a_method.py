# A scalar-expression class attribute declared BELOW a method reads its value through self.
# bug-n-a-scalar-expression-class-attribute-declared-after-a-method-reads-none
class Below:
    def r(self):
        return self.P
    P = (1 + 2)

class Above:
    P = (1 + 2)
    def r(self):
        return self.P

class BelowNoParen:
    def r(self):
        return self.P
    P = 1 + 2

class BelowStr:
    def r(self):
        return self.S
    S = "a" + "b"

print(Below().r(), Above().r(), BelowNoParen().r(), BelowStr().r())
print(Below.P, BelowNoParen.P)
class Below2:
    def r(self):
        return self.P * 2 + 1
    def s(self):
        return self.S.upper() + "!"
    def f(self):
        return self.F / 2
    P = (1 + 2)
    S = "a" + "b"
    F = 1.5 * 3
    N = -(4)
    def late(self):
        return self.P + self.N, f"{self.S}-{self.F:.2f}"

class Above2:
    P = 2 * 5
    L = [1, 2] + [3]
    def r(self):
        return self.P + len(self.L)

b = Below2()
print(b.r(), b.s(), b.f(), b.late(), Below2.P + 1, Below2.S * 2)
print(Above2().r(), Above2.P, Above2.L)
