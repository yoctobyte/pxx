# `not a`, `~a`, `a and 5`, `z or 7` on a name assigned from arithmetic (a
# PROMOTABLE int, `a = x + 1`). `not` complemented the box (True for 1025, so
# `if not a:` took the wrong branch) and and/or returned a Boolean instead of
# the operand. Expected = python3.
# bug-n-not-and-invert-read-the-box-of-a-name-assigned-from-arithmetic
x = 1024
a = x + 1
print(not a)
b = 1025
print(not b)
def f():
    y = 1024
    c = y + 1
    return not c
print(f())
z = a
print(not z, bool(a), a)
for v in [0, 1, -1, 0.0, 2.5, "", "x", [], [0], None, {}, {1: 2}, 2 ** 70, 0 * 2 ** 70]:
    print(not v, end=" ")
print()
if not a:
    print("branch: falsy")
else:
    print("branch: truthy")
print(~a, ~(x + 1), ~(2 ** 70))
big = 2 ** 70
small = big - big
print(not big, not small, not (big + 1), not (x - 1024))
x = 1024
a = x + 1
z = x - 1024
if a:
    print("a truthy")
if z:
    print("z truthy")
else:
    print("z falsy")
print(bool(a), bool(z), a and 5, z or 7, a or 9, z and 3)
n = 3
while n:
    n = n - 1
print("loop", n)
print([v for v in [a, z, x] if v], any([z, z]), all([a, x]))
print(1 if z else 2, "y" if not z else "n")
b = 1025
c = 0
print(b and 5, c or 7, b or 9, c and 3)
x = 1024
a = x + 1
print(a and 5, a or 9)
print(a and "s", 0.0 or a)
