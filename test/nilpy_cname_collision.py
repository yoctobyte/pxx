# Helper for test_nilpy_a_qualified_member_loses_to_a_c_function_of_the_same_name.
#
# `open` is the point of this module. Any C header that declares `int open(...)`
# puts a GLOBAL proc of that name in scope, and the NilPy return-type inference
# walk resolved a qualified member call through the global FindProc -- so
# `m.open(...)` was typed by C's `int`, not by this function.
#
# Returning a CLASS-or-None is what makes the collision observable rather than
# merely wrong: tyInt32 joined against the None arm refuses outright, which is
# how it surfaced as `annotate the type / too dynamic` on the ASSIGNMENT, several
# lines from the call that actually mis-resolved.


class World:
    def __init__(self, p):
        self.p = p

    def get(self):
        return 4 * 100 + 7


class Region:
    def __init__(self, p):
        self.p = p

    def get(self):
        return 4 * 100 + 8


def open(name="x"):
    if name == "tiled":
        return World(name)
    return Region(name) if name else None


# A second colliding name, so the test is not pinned to one C declaration:
# `close` is declared by unistd.h the same way. Not reserved in Python either.
def close(name="x"):
    return World(name) if name else None
