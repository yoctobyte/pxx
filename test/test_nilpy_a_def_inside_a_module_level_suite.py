# A def inside a module-level if/for/try binds a module name, like a depth-0 def.
# bug-n-a-def-inside-a-taken-branch-does-not-rebind-the-name (the refusal half)
import sys
if True:
    def pick():
        return 7
    print(pick())
print(pick())
N = 10
try:
    from nosuchmod import f
except ImportError:
    def f(x):
        return x + 1
print(f(4))
if False:
    def h():
        return 3
def h():
    return 4
print(h())
for i in range(2):
    def k(x):
        return x * N + i
print(k(3))
if sys.platform:
    def plat(a, b=2):
        return a + b
else:
    def plat(a, b=2):
        return a - b
print(plat(5), plat(5, b=7))
try:
    import json
    def enc(x):
        return json.dumps(x)
except ImportError:
    def enc(x):
        return str(x)
print(enc([1, 2]))
def user(n):
    return fact(n) + 1
try:
    from math import nosuchthing
except ImportError:
    def fact(n):
        if n <= 1:
            return 1
        return n * fact(n - 1)
    def inner_user():
        return fact(4)
print(user(5), inner_user())
total = 0
if True:
    def add(x):
        global total
        total += x
        return total
add(3); add(4)
print(total)
if True:
    lam = lambda v: v * 2
    def twice(v):
        return lam(v) + 1
print(twice(5))
lam2 = lambda v: v * 2
if True:
    def twice2(v):
        return lam2(v) + 1
print(twice2(5))
