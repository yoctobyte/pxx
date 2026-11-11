# A keyword argument after more than four positionals through a callable VALUE:
# a plain def and a nested def, keywords in either order, one omitted.
# bug-n-a-keyword-argument-through-a-callable-value-is-refused-above-four-positionals

def aim(a, b, c, d, e, tol=1.0, step=2):
    return a + b + c + d + e + tol + step


def mk(k):
    def inner(a, b, c, d, e, tol=1.0):
        return (a + b + c + d + e) * k + tol
    return inner


fs = [aim, mk(10)]
for f in fs:
    print(f(1, 2, 3, 4, 5, tol=1000.0))
print(fs[0](1, 2, 3, 4, 5, step=7, tol=0.5))


trace = []


def t(v):
    trace.append(v)
    return v


fs[0](t(1), t(2), t(3), t(4), t(5), tol=t(6))
print(trace)
