class World:
    def __init__(self, p):
        self.p = p


def open(name="x"):
    return World(name)
