# Helper module for test_nilpy_relative_import.npy — imported through the
# RELATIVE spellings (`from .nilpy_relhelper import ...`, `from . import
# nilpy_relhelper`). Kept deliberately small: what the test pins is the import
# MECHANISM, not anything this module computes.
VALUE = 41
NAME = "relhelper"


def bump(n):
    return n + 1


class Thing:
    def __init__(self, v):
        self.v = v

    def doubled(self):
        return self.v * 2
