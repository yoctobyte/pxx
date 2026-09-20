# Declares `wind` as a METHOD. Compiled AFTER traffic.py in the driver's import
# order, which is the point of the fixture: when traffic.py's body is lowered
# this class has no rows in the class table yet, so the method scan finds
# nothing and the field scan takes the only carrier it can see.
class Environment:
    def wind(self, x, z):
        return (x + z, 0.5)

    def gust(self, x):
        return x * 3.0
