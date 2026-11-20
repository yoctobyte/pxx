# A parameter or local spelled like a Pascal intrinsic or a Python builtin is
# that binding, as CPython scopes it. `def p(pred, v): return pred(v)` used to
# answer Pascal's Pred(v), and `lo`, `length`, `int`, `trunc`, `next`, ...
# each reached their intrinsic, a wrong value or a bogus TypeError.
# bug-n-a-param-or-local-named-like-a-pascal-intrinsic-is-answered-by-the-intrinsic

def f(x):
    return "f" + str(x)

def by_pred(pred, v):
    return pred(v)

def by_lo(lo, v):
    r = lo(v)
    return r

def by_length(length, v):
    return length(v)

def by_int(int, v):
    return int(v)

def by_trunc(trunc, v):
    return trunc(v)

def by_len(len, v):
    return len(v)

def by_next(next, v):
    return next(v)

def local_succ(v):
    succ = f
    return succ(v)

def local_ord(v):
    ord = f
    print(ord(v))
    return 0

def local_upcase(v):
    upcase = f
    return upcase(v)

print(by_pred(f, 7), by_lo(f, 7), by_length(f, 7), by_int(f, 7))
print(by_trunc(f, 7), by_len(f, 7), by_next(f, 7))
print(local_succ(7), local_upcase(7))
local_ord(7)

# the builtins themselves, where nothing shadows them
print(len("abc"), int("5"), round(2.5), abs(-3), ord("A"), str(4))
def keeps(v):
    return len(v) + int("1")
print(keeps("ab"))

# module level: before the binding the builtin answers, after it the binding
print(round(7.4))
round = f
print(round(7))
