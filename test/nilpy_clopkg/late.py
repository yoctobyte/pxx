from .shapes import Box, Other, scaled


def run():
    b = Box(2.5)
    o = Other()
    # b is a Box and Box descends from Base, so b.size(3) is a Base.size site.
    return b.size(3) + b.area(1.5) + o.area(4, extra=1) + scaled(2.0, factor=0.5)
