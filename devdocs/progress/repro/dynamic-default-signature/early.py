# Imports nothing -- exactly what wind.py does.  And, like wind.py, this module
# declares its OWN class with a method of the same name that accepts the same
# argument count.  That is Wind.at(self, x, z, t=0.0, height=6.0), which sits
# forty lines above the call site in wind.py.
class Breeze:
    def at(self, x, z, t=0.0, height=6.0):
        return "Breeze.at x=%r z=%r t=%r height=%r" % (x, z, t, height)

    def march(self, a, b):
        g = self.grid
        if g is None:
            return "no grid"
        return g.at(a, b)


class Sampler:
    def __init__(self, grid=None):
        self.grid = grid

    def march(self, a, b):
        g = self.grid
        if g is None:
            return "no grid"
        return g.at(a, b)

    def march_named(self, a, b):
        g = self.grid
        if g is None:
            return "no grid"
        return g.sample_zzz(a, b)
