class Ephem:
    def __init__(self, n):
        self.n = n

    def at(self, t):
        return self.n * 10 + t


def epoch():
    return 2451545
