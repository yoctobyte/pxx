# Regression test for bug-n-a-local-bound-to-both-a-pascal-class-and-its-subclass-loses-subscripting
# (closed 2026-11-10: it passes at latest; expected = python3).
import array
class Grid(array.array):
    pass

g = array.array("h", bytes(2))
print(g[0])          # CPython: 0   NilPy: TypeError: object is not subscriptable
g = Grid("h")
