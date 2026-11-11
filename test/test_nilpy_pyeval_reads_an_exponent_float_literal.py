# Exponent float literals through the INTERPRETED path (exec, eval, a lambda
# body pyeval re-lexes): read, and read with the same exact parser float(str)
# uses, so eval('0.3') == 0.3. bug-n-pyeval-cannot-read-an-exponent-float-literal
f = lambda: 1e3
g = lambda x: x * 2.5E-3 + 1_000.5
print(f(), g(4))
ns = {}
exec("a = 1e3\nb = 2.5e-3\nc = 0.1 + 0.2\nd = 1_0.2_5\ne = 3E+2\nh = 7.", ns)
print(ns["a"], ns["b"], ns["c"], ns["d"], ns["e"], ns["h"])
print(eval("0.3") == 0.3, eval("1e-7"), eval("123.456e2"))
