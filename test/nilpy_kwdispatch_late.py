# Imported SECOND — see nilpy_kwdispatch_early.py and the .npy that pulls both.
class Grid:
    def at(self, x, z, outside=0.0):
        return x * z + outside


class Span:
    def reach(self, n, span=0):
        return n * 100 + span
