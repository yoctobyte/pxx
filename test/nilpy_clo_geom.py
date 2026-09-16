# Helper for test_nilpy_call_sites_are_visible_across_modules.npy. Its defs
# have NO call sites in this file: every caller lives in nilpy_clo_user.py or
# in the main module, so the typing below is only possible when the whole
# import closure is lexed before this module's headers are parsed.
class Grid:
    def __init__(self, cols, rows):
        self.cols = cols
        self.rows = rows

    def at(self, x, z):
        return x * 2.0 + z + self.cols


class Route:
    def at(self, distance):
        return distance * 3


def measure(text, scale=1):
    return len(text) * scale
