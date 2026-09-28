# Top-level statements of an imported module must mean what they mean in a
# main program. Compiled both ways by the Makefile against one .expected:
# as the main program, and imported by
# test_nilpy_a_module_top_level_behaves_as_a_main_program.npy.
#
# Before the fix, imported: a late `def abs`/`def len` shadowed the builtin
# ABOVE its def (99 99, 42 42), a redefined def kept its first body (1 1), and
# `vm._p += 5` on a dynamic attribute was dropped (10) -- the receiver of a def
# in a module is a Variant, and that arm had no augmented store. The last one
# also failed in a main program for any unpinned receiver: see f_any.


class VM:
    def __init__(self) -> None:
        self.n = 0


class Other:
    def __init__(self) -> None:
        self.q = 0


def f(vm: VM) -> int:
    vm._p = 10
    vm._p += 5
    return vm._p


def f_any(vm):
    vm._p = 10
    vm._p += 5
    vm._p *= 2
    vm._s = "a"
    vm._s += "b"
    return str(vm._p) + vm._s


print("dynattr", f(VM()))
print("dynattr_any", f_any(VM()), f_any(Other()))
v = VM()
v._p = 1
v._p += 2
print("dynattr_top", v._p)

print("abs_before", abs(-5))


def abs(x):
    return 99


print("abs_after", abs(-5))

print("len_before", len([1, 2]))


def len(x):
    return 42


print("len_after", len([1, 2]))


def g():
    return 1


print("g_first", g())


def g():
    return 2


print("g_second", g())

n = 1
n += 2


def bump():
    global n
    n += 10


bump()
print("global", n)
k = 3


def rd():
    return k * 2


k = 5
print("late_global", rd())
d = {"a": 1}
d["a"] += 5
xs = [1]
xs += [2]
print("containers", d["a"], xs)
