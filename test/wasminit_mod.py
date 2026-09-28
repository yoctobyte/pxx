# Module for test_nilpy_an_imported_modules_top_level_runs_on_wasm32: every
# name below is set by module-level code, which runs as the module's init.
X = 40 + 2
NAMES = ["a", "b", "c"]
TABLE = {"k": 7}


class Box:
    def __init__(self, v):
        self.v = v


BOX = Box(X * 2)
COUNT = 0


def bump():
    global COUNT
    COUNT = COUNT + 1
    return COUNT
