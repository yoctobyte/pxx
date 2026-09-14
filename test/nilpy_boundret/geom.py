class Box:
    def __init__(self, planes):
        self.planes = planes

    def sees(self, x, y, z, radius):
        for a, b, c, d in self.planes:
            if a * x + b * y + c * z + d < -radius:
                return False
        return True
