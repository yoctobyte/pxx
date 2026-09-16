class Base:
    def size(self, k):
        return k * 2


class Box(Base):
    def __init__(self, w):
        self.w = w

    def area(self, scale):
        return self.w * scale


class Other:
    def area(self, scale, extra=0):
        return scale + extra


def scaled(v, factor=1):
    return v * factor
