# Regression test for bug-n-len-does-not-dispatch-len-dunder-on-a-dynamically-typed-value
# (closed 2026-11-10: it passes at latest; expected = python3).
class C:
    def __init__(self):
        self._k = [7, 8, 9]
    def __len__(self):
        return len(self._k)

lst = [C(), C()]
print(len(lst[0]))

d = {"a": C()}
def lp(x):
    return len(x)
def rec(n):
    if n == 0:
        return C()
    return rec(n - 1)
print(len(d["a"]), lp(C()), len(rec(2)))
