# A generator def NESTED in a def segfaulted on its first call: it was registered
# as a plain routine while its body compiled as a step function. Captures of
# the enclosing locals ride as trailing generator parameters.
# bug-n-a-generator-def-nested-in-a-def-segfaults
def gen():
    def g(n):
        for i in range(n):
            yield str(i)
    return list(g(5))
print(gen())

def counter(start, step):
    def walk(n):
        x = start
        for _ in range(n):
            yield x
            x += step
    return [v for v in walk(4)]
print(counter(10, 3))

def pairs(words):
    sep = "-"
    def joined(k=2):
        for w in words:
            yield w * k + sep
    out = []
    for s in joined():
        out.append(s)
    for s in joined(1):
        out.append(s)
    return out
print(pairs(["a", "b"]))

def total(xs):
    def sq():
        for x in xs:
            yield x * x
    return sum(sq())
print(total([1, 2, 3]))

def phase(fn):
    return fn()
print(phase(gen))
