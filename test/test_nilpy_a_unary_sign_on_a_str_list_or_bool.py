# Unary -/+ on an operand that is no plain number. A str or list-typed operand
# used to be negated as a POINTER and then reference-counted (a segfault inside
# the def); a bool kept its type (-True printed True). Now: CPython's TypeError,
# and an int for a bool. bug-n-reading-the-typeerror-a-unary-minus-raised-inside-a-def-segfaults
def neg(v):
    return -v
def pos(v):
    return +v
for f, a in [(neg, "s"), (pos, "s"), (neg, [1]), (pos, {1: 2}), (neg, 3), (neg, 2.5), (pos, 4)]:
    try:
        print(f(a))
    except TypeError as e:
        print("TypeError:", e)
try:
    neg("s")
except TypeError as e:
    print("TypeError:", e)
s = "abc"
try:
    print(-s)
except TypeError as e:
    print("TypeError:", e)
xs = [1, 2]
try:
    print(-xs)
except TypeError as e:
    print("TypeError:", e)
print(-len(s), -(3 - 5), +True, -True)
b = True
print(+True, -True, -b, +b, -False)
class C:
    pass
try:
    print(-C())
except TypeError as e:
    print("TypeError:", e)
