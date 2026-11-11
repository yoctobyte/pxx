# A `**kwargs`-collecting callee reached through a callable value: a module
# def bound to a name, a dict of handlers, a nested def with a capture, and the
# decorator idiom `def wrapper(*args, **kwargs): return fn(*args, **kwargs)`.
# Every shape raised TypeError (the collector was counted as a required
# parameter), a nested def with **kw segfaulted, and a `*args` wrapper died on
# any str argument ("expected a number, got str").
# feature-n-a-kwargs-collecting-callee-through-a-callable-value
def f1(a, **kw):
    return a

def f2(a, lo=7, **kw):
    return a + lo

def f3(a, lo=7, *rest, **kw):
    return a + lo + len(rest) * 100 + len(kw) * 1000

def show(tag, **opts):
    return tag + ":" + ",".join(k + "=" + str(v) for k, v in opts.items())

def fwd(fn, *args, **kw):
    return fn(*args, **kw)


class Btn:
    def __init__(self):
        self.seen = {}

    def config(self, name, **kw):
        for k in kw:
            self.seen[k] = kw[k]
        return name + str(len(kw))


zz = f1
print(zz(1))
zz = f2
print(zz(1), zz(1, 2), zz(1, lo=3, extra=9))
zz = f3
print(zz(1), zz(1, 2), zz(1, 2, 3, 4), zz(1, 2, 3, k=1, j=2))
s = show
print(s("t"), s("t", a=1, b="x"))
b = Btn()
cfg = b.config
print(cfg("w"), cfg("w", fg="red", bg="blue"), sorted(b.seen.items()))
handlers = {"show": show, "f2": f2}
print(handlers["show"]("h", z=0), handlers["f2"](5, lo=1, q=2))
try:
    zz = f2
    zz(1, 2, 3)
except TypeError:
    print("TypeError")


def outer(base):
    def inner(a, **kw):
        return base + a + len(kw)
    return inner


g = outer(10)
print(g(1), g(1, p=1, q=2))


def logged(fn):
    def wrapper(*args, **kwargs):
        print("call", fn.__name__, len(args), sorted(kwargs))
        return fn(*args, **kwargs)
    return wrapper


def retry(times):
    def deco(fn):
        def wrapper(*args, **kwargs):
            last = None
            for _ in range(times):
                last = fn(*args, **kwargs)
            return last
        return wrapper
    return deco


@logged
def add(a, b=1):
    return a + b


@retry(3)
def greet(name, punct="!"):
    return "hi " + name + punct


print(add(2), add(2, 3), add(2, b=5))
print(greet("x"), greet("y", punct="?"))
