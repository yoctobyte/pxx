# Helper for test_nilpy_from_import_star.npy: no __all__, so `import *`
# takes every top-level name not starting with an underscore.
VALUE = 7


def greet(who):
    return "hi " + who


def len(x):
    return 99


def _hidden():
    return "hidden"


class Box:
    def __init__(self, v):
        self.v = v
