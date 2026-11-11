# A generator called from a def ABOVE its own def crashed: the call baked in an
# instance size and slot offsets that only exist once the body is compiled.
# Such a call now goes through the generator's factory. Keyword arguments to a
# generator call bind by name.
# bug-nilpy-a-generator-called-above-its-def-crashes
SCALE = 3
def early():
    return list(gen(2)) + list(gen(3, k=SCALE)) + [v for v in gen(2, xs=None)]
def early_for():
    out = []
    for v in gen(4):
        out.append(v)
    return out
def gen(n, k=1, xs=None):
    i = 0
    while i < n:
        yield i * k
        i += 1
print(early())
print(early_for())
g = gen(3)
print(next(g), next(g))
def kw_after():
    return list(gen(xs=[1], n=2, k=5))
print(kw_after())
print(list(gen(2, k=10)))
