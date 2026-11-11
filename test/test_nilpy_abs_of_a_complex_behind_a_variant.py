# abs() of a complex that arrives as a VARIANT (a ** result, a list element):
# its magnitude, as a statically typed complex already gave. The ** row is
# rounded: the power's own last bits differ from CPython's, and that is
# accepted (performance-beats-last-ULP-parity). bug-n-abs-of-a-complex-raises-typeerror
z = (-8.0) ** 0.5
print(type(z).__name__, round(abs(z), 12))
w = complex(3, -4)
print(abs(w), abs(-w), abs(complex(0, 0)))
zs = [complex(6, 8), complex(-5, 12)]
print([abs(q) for q in zs])
