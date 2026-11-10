# Regression test for bug-nilpy-a-generator-returned-from-a-def-yields-nothing
# (closed 2026-11-10: it passes at latest; expected = python3).
def gen(n):
    yield n
    yield n + 1
def mk():
    return gen(5)
print(list(mk()))     # [] ; CPython [5, 6]
x = mk()
print(next(x))        # compile error: no overload of next matches these arguments
