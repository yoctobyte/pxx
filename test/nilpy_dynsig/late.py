# Pulled AFTER early.py, which is the whole point: the class that the receiver
# actually IS cannot be a candidate when early.py's call sites are compiled.
# Its defaults differ from Breeze's in VALUE as well as in count, so a fill
# from the wrong signature cannot be mistaken for a correct one -- 77.5 is not
# 0.0 and not 6.0.
class Grid:
    def at(self, x, z, outside=77.5):
        return "Grid x=%r z=%r outside=%r" % (x, z, outside)

    def sample_zzz(self, x, z, outside=77.5):
        return "Gzzz x=%r z=%r outside=%r" % (x, z, outside)
