# a, b = <callable>, <callable> binds callable names, like a = <callable>.
# bug-n-a-tuple-unpacking-assignment-does-not-box-a-callable-value
def inc(x):
    return x + 1
def dbl(x):
    return x * 2
a, b = lambda x: x + 1, lambda x: x + 2
print(a(1), b(1))
f, g = inc, dbl
print(f(3), g(3))
h, n = inc, 1
print(h(n))
def mk(k):
    p, q = (lambda x: x + k), (lambda x: x * k)
    return p(2) + q(2)
print(mk(10))
