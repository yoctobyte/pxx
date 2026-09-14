import geom

PLANES = [(1.0, 0.0, 0.0, 0.0), (0.0, 1.0, 0.0, 0.0)]


def probe():
    box = geom.Box(PLANES)
    return box.sees(1.0, 2.0, 3.0, 0.5)
