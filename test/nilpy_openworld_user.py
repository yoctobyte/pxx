# Every call here is on a parameter -- a dynamically typed receiver -- naming a
# method NO class declares at the point this file is parsed. Before 2026-09-10
# each one was a hard compile error and this module could not exist.


def blows(canopy, sx, sz):
    return canopy.contains(sx, sz)


# a FLOAT argument and a bool answer: the receiver is still dynamic, so the
# call goes through pyeval's mixed family (one double, a register result),
# whose Boolean must come back as True/False and not as 1/0 (2026-09-16)
def warm(canopy, t):
    return canopy.hot(t)


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
