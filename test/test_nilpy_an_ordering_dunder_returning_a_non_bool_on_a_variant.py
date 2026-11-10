# Regression test for bug-n-an-ordering-dunder-that-returns-a-non-bool-fails-against-a-variant-operand
# (closed 2026-11-10: it passes at latest; expected = python3).
class RBool:
    def __lt__(self, o):
        return True


class RStr:
    def __lt__(self, o):
        return "LT"


class Par:                       # k arrives through a PARAMETER -> variant
    def __init__(self, k=11.0):
        self.k = k


par = Par()
print("bool return, variant operand ->", RBool() < par.k)   # True  -- correct
print("str  return, LITERAL operand ->", RStr() < 11.0)     # LT    -- correct
print("str  return, variant operand ->", RStr() < par.k)    # TypeError
