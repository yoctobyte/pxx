# `lo`, `hi` and `abs` case-fold onto Pascal's Lo/Hi/Abs; a module binding of
# the exact spelling is what the name means. Before the fix lo(2) printed 2 and
# hi(2) printed 0 -- the intrinsic's answer.
# bug-n-a-local-holding-a-callable-is-shadowed-by-a-pascal-intrinsic-at-the-call
def f(x):
    return "f " + str(x)

print(abs(-5))      # above the binding: still the builtin
lo = f
print(lo(2))
hi = f
print(hi(2))
ord = f
print(ord(2))
abs = f
print(abs(2))

def g():
    lo = f
    hi = f
    return lo(3) + " " + hi(4)
print(g())

def h():
    abs = f
    return abs(7)
print(h())
