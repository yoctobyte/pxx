# Values that differed between x86-64 and the 32-bit targets, and one that
# crashed on every target, found by the 2026-09-28 Nil Python cross-target
# differential (the test corpus built for i386/aarch64/arm32 at -O2, diffed
# against x86-64 and CPython). Each block names its ticket.
import math

# a stackless generator driven through a cursor: next() and list()
# bug-a-i386-a-stackless-generator-called-through-a-cursor-reads-its-instance-from-the-wrong-slot
def gen(n):
    i = 0
    while i < n:
        yield i * 10
        i += 1
g = gen(4)
print(next(g), next(g))
print(list(gen(3)))

# a str-literal argument (the parameter is inferred AnsiString)
# bug-nilpy-a-generator-called-with-a-str-literal-segfaults
def chars(s):
    for c in s:
        yield c + "!"
for x in chars("hi"):
    print(x)
print(list(chars("ab")))

# %x / %o / format on an Int64-range value
# bug-nilpy-a-32-bit-target-refuses-x-and-o-on-an-int64-range-value
lo = -2**63
hi = 2**63 - 1
print("%x" % lo, "%o" % hi, format(hi, "x"), "{:X}".format(2**40 + 5))

# a def read back through a callable value, with and without *args
# bug-a-a-callable-values-signature-record-is-misread-on-32-bit-targets
def q(a, b=7):
    return (a, b)
f = q
print(f(1), f(1, 2))
def star(*args):
    return len(args)
h = star
print(h(1, 2, 3), h())

# float -> int past 2^31
# bug-a-arm32-nilpy-float-to-int-saturates-at-32-bits
big = 3000000000.7
print(int(big), math.floor(big), math.trunc(big), round(big), math.ceil(-big))
print(int(-5e9), round(2.5e10))
