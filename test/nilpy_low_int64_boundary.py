# Low(Int64) is the ONE value in Int64 whose MAGNITUDE the type cannot hold, so
# anything that takes |v| by negating in place is wrong there and correct at
# every neighbour -- including Low(Int64)+1, which is why a sweep that steps by
# one either side of the interesting value does not find it. The rows below sit
# ON it and on both neighbours.
#
# This repo has now hit that boundary through two renderers: aarch64's WriteLn
# digit loop (bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes,
# done, fixed by sdiv -> udiv AFTER the neg made the value a magnitude) and
# NilPy's abs()/%d.
#
# DELIBERATELY ABSENT: `"%d" % -9223372036854775808`, which still emits a bare
# `-` -- sign, no digits -- while print() and %s are both correct on the same
# value. That half is open; this file must not be read as covering it.
# bug-a-low-int64-renders-as-a-bare-minus-under-percent-d-and-abs-of-it-stays-negative

LOW = -9223372036854775808

print("abs low      ", abs(LOW))
print("abs low+1    ", abs(LOW + 1))
print("abs low-1    ", abs(LOW - 1))
print("abs -2^62    ", abs(-4611686018427387904))
print("abs +2^63    ", abs(9223372036854775808))
print("abs -1       ", abs(-1))
print("abs 0        ", abs(0))

# The result must be a NUMBER that arithmetic works on, not text that happens
# to print right -- an abs() returning a string would pass a printed-value
# check and fail every use.
print("low+1 arith  ", abs(LOW) + 1)
print("low//2 arith ", abs(LOW) // 2)
print("low*2 arith  ", abs(LOW) * 2)
print("low-1 arith  ", abs(LOW) - 1)
print("compare      ", abs(LOW) > 9223372036854775807)

# Rendering the value itself, through the spellings that are correct today.
print("print        ", LOW)
print("str          ", str(LOW))
print("%s           ", "%s" % LOW)
print("neg of it    ", -LOW)
print("via shift    ", -1 << 63)

print("DONE")
