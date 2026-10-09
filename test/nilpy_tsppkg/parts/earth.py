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
