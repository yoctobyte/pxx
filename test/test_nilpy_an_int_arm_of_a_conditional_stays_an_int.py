# A conditional expression SELECTS an arm unchanged: an int arm against a float
# arm is still the int (CPython prints 0, not 0.0), and the result keeps
# working in arithmetic, typed parameters and comparisons.
# bug-n-an-int-arm-of-a-conditional-expression-is-rendered-as-a-float
import math
def g(y):
    return 0 if y is None else float(y)
print(repr(g(None)), repr(g(2)))
def h(y):
    return 0 if y else 1.5
print(repr(h(0)), repr(h(1)))
y = None
print(repr(0 if y is None else float(y)))
z = 3 if y is None else 2.5
print(z, repr(z))
xs = [1 if i % 2 else 0.5 for i in range(3)]
print(xs)
def half(v: float) -> float:
    return v / 2
for c in [True, False]:
    w = 4 if c else 2.25
    print(repr(w), w * 2, w + 1, int(w), math.sqrt(w), half(w), w > 3, str(w))
c = False
a = 7 if c else 7
b = 1.5 if c else 2.5
print(repr(a), repr(b))
