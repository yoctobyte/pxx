# A generator def taken as a VALUE is called through its factory, not through
# its step routine: `c = count; c(3)` handed 3 to the hidden instance parameter
# ("missing 1 required positional argument(s)"). Defaults, keyword arguments,
# `*args` forwarding, `__name__`, and a value bound in a statically dead arm.
# Expectations are CPython's own output.
def count(n, step=1):
    i = 0
    while i < n:
        yield i
        i += step
def run(factory, *args):
    return list(factory(*args))
c = count
print(list(c(3)), list(c(6, 2)))
print(run(count, 4), run(count, 7, 3))
print(c.__name__)
gens = {"a": count}
print(sum(gens["a"](5)))
for v in c(2):
    print("v", v)
print(list(count(3)))
if True:
    def _g():
        yield 1
    gen = _g
else:
    def _h():
        yield 9
    gen = _h
print(list(gen()))
