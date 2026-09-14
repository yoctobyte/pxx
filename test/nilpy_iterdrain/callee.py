# The CALLEE, and it has to live in a module of its own: a def in the main
# module resolves by another path and never reaches the overload retry.


def with_default(c, title="T"):
    return c.label() + "/" + title


def no_default(c):
    return c.label()
