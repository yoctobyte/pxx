# A bare tuple on the right of `=` binds a tuple, as `return a, b` returns
# one: in a def, at module scope, and as a chained target's shared value.
# And adjacent string/bytes literals join across a COMMENT, trailing or on its
# own line, inside brackets, while a statement-level newline still separates.
def rtc(y):
    wday = 3
    result = y, 9, 25, 12, 30, 0, wday - 1, 0
    return result

x = 1, 2
p = q = "a", 2
single = 7,
print(rtc(26), x, p, q, single, len(single))
s = ("ab"  # one
     "cd")
b = (b"ab"  # one
     b"cd")
o = ("ab"
     # own line, with a "quote"

     "cd"  # after
     f"{1 + 1}")
t = "p"  # not joined at statement level
"z"
print(s, b, o, t, len(o))
