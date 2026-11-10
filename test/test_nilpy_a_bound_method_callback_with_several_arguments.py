# Regression test for feature-nilpy-multi-arg-callback-bridges
# (closed 2026-11-10: it passes at latest; expected = python3).
class C:
    def add(self, a, b): return a + b
def call2(f): return f(4, 5)
print(call2(C().add))      # 9

class K:
    def add3(self, a, b, c): return a + b + c
def call3(f): return f(1, 2, 3)
print(call3(K().add3), call3(lambda a, b, c: a * b * c))
