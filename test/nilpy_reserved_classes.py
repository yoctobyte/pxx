# Helper for test_nilpy_a_module_member_named_like_a_pascal_keyword.
#
# A CLASS named like a Pascal keyword is a SECOND site, not the same one as a
# function: the qualified-CONSTRUCTION arm asked only whether the UNDERSCORED
# spelling was a constructor name, so `m.set(...)` was never recognised as a
# construction at all and fell through to the member path, which then missed too.
#
# These live in their own module rather than beside the functions on purpose. Put
# `class record` into a module that already has `def record` and Python REBINDS
# the name -- the class silently wins, and every function row in the other
# fixture would pass while testing the class instead.
class set:
    def __init__(self, n):
        self.n = n

    def get(self):
        return self.n * 10 + 1


class type:
    def __init__(self, n):
        self.n = n

    def get(self):
        return self.n * 10 + 2


class record:
    def __init__(self, n):
        self.n = n

    def get(self):
        return self.n * 10 + 3


# Not reserved anywhere: if this row fails the harness never reached this module
# and none of the rows above mean what they appear to.
class Ordinary:
    def __init__(self, n):
        self.n = n

    def get(self):
        return self.n * 100 + 99
