# A module name bound by several `def` statements, at least one inside a
# module-level suite, is bound by the def statement that RAN LAST -- the
# platform idiom picked the first arm whatever ran. Lowered in the lexer
# (PyCondDefRebind) to `name = <hidden def>` after each body.
# Also: a name assigned only inside a module-level suite is visible to a def
# written ABOVE it (`HAVE` below was "undefined variable").
# bug-n-a-def-inside-a-taken-branch-does-not-rebind-the-name
# Expectations are CPython's own output.
def have():
    return HAVE
try:
    import nosuchmod_condef26
    HAVE = True
except ImportError:
    HAVE = False
print(have())
import sys
def early():
    return plat(3) + "!"
if sys.platform == "win32":
    def plat(x):
        return "w" + str(x)
else:
    def plat(x):
        return "p" + str(x)
print(plat(1), early(), plat.__name__)
def g():
    return 1
print(g())
if True:
    def g():
        return 2
print(g())
if False:
    def g():
        return 3
print(g())
try:
    from nosuchmod_q import isqrt
except ImportError:
    def isqrt(n):
        r = 0
        while (r + 1) * (r + 1) <= n:
            r += 1
        return r
print(isqrt(17))
for i in range(3):
    def h(): return i
print(h())
if True:
    def pick():
        return 7
print(pick())
def fact(n):
    return 1 if n < 2 else n * fact(n - 1)
if sys.platform != "x":
    def fact(n, acc=1):
        return acc if n < 2 else fact(n - 1, acc * n)
print(fact(5), fact(5, 2))
if sys.platform == "x":
    def walk(n):
        yield -n
else:
    def walk(n, step=1):
        i = 0
        while i < n:
            yield i
            i += step
print(list(walk(4)), list(walk(6, 2)), walk.__name__)
for v in walk(2):
    print(v)
