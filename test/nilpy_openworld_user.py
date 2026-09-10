# Every call here is on a parameter -- a dynamically typed receiver -- naming a
# method NO class declares at the point this file is parsed. Before 2026-09-10
# each one was a hard compile error and this module could not exist.


def blows(canopy, sx, sz):
    return canopy.contains(sx, sz)


def a0(o):
    return o.zero()


def a1(o):
    return o.one(1)


def a2(o):
    return o.two(1, 2)


def a3(o):
    return o.three(1, 2, 3)


def a4(o):
    return o.four(1, 2, 3, 4)
