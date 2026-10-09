# A typed tuple/list parameter, reached through a PLAIN from-import inside a
# MODULE. The module re-exports `first` as a module-level var, and calls here
# went through that var dynamically: the callee got a boxed Variant where its
# `a: tuple` expects the object -- IndexError or a segfault (TSP, vec/earth).
from .vec import big, first, pair
from nilpy_tsppkg.parts.vec import head


def f1() -> float:
    a = (1.0, 2.0)
    return first(a)


def f2() -> float:
    a = (1.0, 2.0)
    return pair(a, a)


def f3() -> tuple:
    a = (1.0, 2.0)
    return big(a, a)


def f4() -> float:
    return first((3.0, 4.0)) + head([5.0, 6.0])


def f5() -> float:
    # a FUNCTION-LOCAL renaming import: `f` holds the function object, so
    # vec.first must take the variant ABI or `f(a)` reads garbage
    from .vec import first as f
    a = (7.0, 8.0)
    return f(a)
