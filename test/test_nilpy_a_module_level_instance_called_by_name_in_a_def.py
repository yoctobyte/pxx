# `v(1.0)` on a module-level instance is v.__call__(1.0), never V(1.0) -- in
# every position. The rows CPython agrees on are the ticket's table.
# bug-n-a-module-level-instance-called-by-name-in-a-function-constructs-instead-of-calling
class V:
    def __init__(self, x=0.0):
        self.x = x
    def __call__(self, a):
        return "CALL"

class Thing:
    def __call__(self, a):
        return "THING"

v = V(22.0)
inst = V(1.0)
thing = Thing()

def r1():
    return v(1.0)
def r2():
    return v(1.0)
def r3():
    x = v(1.0)
    return x
def r4(p):
    return v(p)
def r5():
    r = None
    r = v(1.0)
    return r
def r6():
    if True:
        return v(1.0)
    return None
def r7():
    return v(1.0), 1
def r9():
    f = v
    return f(1.0)
def r10():
    w = V(3.0)
    return w(1.0)
def r11(q):
    return q(1.0)
def r12():
    return inst(1.0)
def r13():
    return thing(2)
def r14():
    return V(5.0).x

print(r1(), r2(), r3(), r4(2.0), r5(), r6(), r7()[0])
print(v(1.0), r9(), r10(), r11(v), r12(), r13(), r14())
