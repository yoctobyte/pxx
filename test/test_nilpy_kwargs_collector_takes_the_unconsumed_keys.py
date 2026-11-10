# Regression test for bug-n-kwargs-collector-alongside-named-params-needs-the-remainder
# (closed 2026-11-10: it passes at latest; expected = python3).
def f(a=1, **kw):
    return a * 100 + len(kw)

print(f(**{"a": 5, "x": 7, "y": 8}))
