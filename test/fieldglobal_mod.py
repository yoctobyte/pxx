# Module globals read into another module's fields -- see
# test_nilpy_a_field_from_another_module_s_global.npy. The def and the class
# are the TRIGGER, not scenery: without a def here the importer's field
# pre-pass found these names in rows this module left behind, and passed.
LIMIT = 7


class K:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def norm1(self):
        return abs(self.x) + abs(self.y)


def helper(n):
    return n * 2


NAME = "st"
ON = True
ORIGIN = K(3, 4)
VIEW = 1700.5
