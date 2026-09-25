# A def that returns nothing -- no return, a bare return, or falling off
# the end after an if -- yields None as a value, read through is None, ==
# and print.  Always-exit bodies keep their narrow result type.
class A:
    def m(self, v):
        print("m", v)
    def bare(self):
        return
    def cond(self, x):
        if x > 0:
            return x
    def val(self):
        return 3
def f(v):
    print("f", v)
def g():
    return
def h(x):
    if x > 0:
        return x
def show(tag, r):
    print(tag, r, r is None, r == None)
a = A()
show("meth", a.m(1))
show("bare", a.bare())
show("cond+", a.cond(2))
show("cond-", a.cond(-1))
show("val", a.val())
show("func", f(2))
show("gbare", g())
show("h+", h(5))
show("h-", h(-5))
r = a.m(3)
if r is None:
    print("None branch")
else:
    print("value branch", r)
r2 = f(4)
print(r2)
x = g()
print(x is None)
def ifelse(x):
    if x > 0:
        return 1
    elif x < 0:
        return -1
    else:
        return 0
def loop(x):
    while True:
        x += 1
        if x > 5:
            return x
def rz(x):
    raise ValueError("no")
def lastret(x):
    y = x + 1
    return y
def gen(n):
    for i in range(n):
        yield i
def noelse(x):
    if x > 0:
        return 1
def brk(x):
    while True:
        if x > 3:
            break
        x += 1
class C:
    def __init__(self, v):
        self.v = v
    def get(self):
        return self.v
print(ifelse(2), loop(1), lastret(1), list(gen(3)), noelse(-1), brk(0), C(4).get())
