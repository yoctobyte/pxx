# A keyword argument on a run-time-dispatched call that resolves to a CALLABLE
# FIELD binds by name against the callable's own signature record (a lambda,
# a plain def), with defaults for what is omitted. It used to be refused as
# "takes positional arguments only"; this file was nilpy_open_world_kwarg_fail.
# bug-n-a-keyword-argument-through-a-callable-field-is-refused

class Holder:
    def go(self, x, mode=1):
        return x


def call(o):
    return o.zap(1, mode=2)


def call2(o):
    return o.zap(n=5)


class Box:
    def __init__(self):
        self.v = 0


def plain(n, mode=0):
    return n * 10 + mode


b = Box()
b.zap = lambda n, mode=0: n + mode
print(call(b))
print(call2(b))
c = Box()
c.zap = plain
print(call(c))
print(call2(c))
try:
    c.zap(1, nope=3)
except TypeError:
    print("TypeError")
