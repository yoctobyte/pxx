# Imports NOTHING, and declares its own class with a method of the name the
# sibling module also uses. This is wind.py's exact shape: the candidate scan
# runs while this module is being parsed, so the only `.at` it can see is the
# one FORTY LINES UP, in this same file.
class Breeze:
    def at(self, x, z, t=0.0, height=6.0):
        return "Breeze t=%r height=%r" % (t, height)


class Sampler:
    def __init__(self, grid=None):
        self.grid = grid

    # The receiver has no static type whatsoever, so every call below is
    # dispatched on it -- with a signature the scan guessed from Breeze.
    def defaulted(self, a, b):
        return self.grid.at(a, b)

    def unique_name(self, a, b):
        return self.grid.sample_zzz(a, b)
