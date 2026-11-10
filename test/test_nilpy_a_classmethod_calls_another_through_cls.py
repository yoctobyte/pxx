# Regression test for bug-n-a-classmethod-cannot-call-another-through-cls
# (closed 2026-11-10: it passes at latest; expected = python3).
class C:
    def __init__(self, v: int):
        self.v = v
    @classmethod
    def make(cls, v: int):
        return cls(v)
    @classmethod
    def twice(cls, v: int):
        return cls.make(v * 2)      # AttributeError: 'type' object has no attribute 'make'
class D(C):
    pass
print(C.twice(5).v)                 # CPython: 10.   pxx: raises
