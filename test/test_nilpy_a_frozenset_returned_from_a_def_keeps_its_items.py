# Regression test for bug-n-a-frozenset-returned-from-a-def-arrives-empty
# (closed 2026-11-10: it passes at latest; expected = python3).
def f():
    return frozenset([1, 2, 3])

print(len(f()))       # pxx: 0        CPython: 3
print(repr(f()))      # pxx: frozenset()   CPython: frozenset({1, 2, 3})
print(1 in f())       # pxx: False    CPython: True
