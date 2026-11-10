# Regression test for bug-n-tuple-unpacking-of-an-inline-tuple-does-not-unpack-iterable-values
# (closed 2026-11-10: it passes at latest; expected = python3).
from xml.etree.ElementTree import Element
a, b = Element("a"), Element("b")
print(type(a).__name__, type(b).__name__)

class It:
    def __init__(self, t): self.t = t
    def __iter__(self): return iter([self.t])
p, q = It("p"), It("q")
p, q = q, p
print(p.t, q.t)
