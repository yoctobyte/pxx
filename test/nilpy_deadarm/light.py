# The handler's module: the one CPython actually imports, and the one every row
# below must read its answer from.
SHARED = 27


def who():
    return "light"
