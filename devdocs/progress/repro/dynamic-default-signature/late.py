class Grid:
    def at(self, x, z, outside=None):
        return "Grid.at x=%r z=%r outside=%r" % (x, z, outside)

    def sample_zzz(self, x, z, outside=None):
        return "Grid.szz x=%r z=%r outside=%r" % (x, z, outside)
