import geom
import early


def draw():
    box = geom.Box(early.PLANES)
    print("direct  ", box.sees(1.0, 2.0, 3.0, 0.5))
    sees = box.sees
    print("hoisted ", sees(1.0, 2.0, 3.0, 0.5))
