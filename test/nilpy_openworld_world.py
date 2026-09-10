# The class the call sites in nilpy_openworld_user.py never see at compile time.
# Imported SECOND by the test, so at the moment those bodies are parsed no class
# in the unit declares any of these names -- which is the whole point.


class Canopy:
    def __init__(self, n):
        self.n = n

    def contains(self, x, z):
        return x + z < self.n

    def zero(self):
        return "z" + str(self.n)

    def one(self, a):
        return a + 1

    def two(self, a, b):
        return a + b

    def three(self, a, b, c):
        return a + b + c

    def four(self, a, b, c, d):
        return a + b + c + d
