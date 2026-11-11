# Two defs of one name in one function: the def that RAN is the one called.
# bug-n-two-same-named-defs-in-exclusive-branches-of-one-function-collapse-silently
def outer(flag):
    if flag:
        def pick():
            return 7
    else:
        def pick():
            return 9
    return pick()

def arity(flag):
    if flag:
        def pick(a):
            return a + 1
        return pick(1)
    else:
        def pick(a, b):
            return a * b
        return pick(3, 4)

def seq():
    def pick():
        return 7
    a = pick()
    def pick():
        return 9
    return (a, pick())

def captures(flag, base):
    scale = 10
    if flag:
        def f(x):
            return base + x
    else:
        def f(x):
            return base * scale + x
    return [f(i) for i in range(3)]

def loop():
    out = []
    for i in range(3):
        def g(x):
            return x * 10
        out.append(g(i))
    return out

def trybody():
    try:
        def h():
            return 7
    except ValueError:
        def h():
            return 8
    return h()

print(outer(True), outer(False))
print(arity(True), arity(False))
print(seq())
print(captures(True, 5), captures(False, 5))
print(loop(), trybody())
