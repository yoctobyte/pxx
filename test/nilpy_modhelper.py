# Imported by test_nilpy_py_module_import.npy. A module is a real compilation
# unit: its defs, classes and module-level names are the unit's, and its
# top-level code is the unit's initialisation.
print("module init ran")

COUNT = 3
NAMES = ["a", "b"]


def twice(x):
    return x * 2


class Box:
    def __init__(self, v):
        self.v = v

    def get(self):
        return self.v
