# SPDX-License-Identifier: 0BSD
# An import in a function body runs when the function reaches it, so a module
# that does not exist is ModuleNotFoundError at that line, not a compile error
# (umqtt.simple: `if self.ssl is True: import ssl`). Expected is CPython 3.
import math


def f(use):
    if use:
        import no_such_module_xyz
        return no_such_module_xyz.thing()
    return 1


def g():
    from no_such_pkg_abc import helper
    helper()
    return 2


def h():
    import math
    return int(math.sqrt(16))


def one_line(use):
    if use: import no_such_one_line
    return 3


print(f(False))
try:
    f(True)
except ImportError as e:
    print("ImportError:", e)
try:
    g()
except ModuleNotFoundError as e:
    print("ModuleNotFoundError:", e)
print(h())
print(one_line(False))
try:
    one_line(True)
except ImportError as e:
    print("ImportError:", e)
print(math.floor(2.5))
