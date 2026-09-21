# Declares `wind` as a METHOD. Compiled AFTER traffic.py in the driver's import
# order, which is the point of the fixture: when traffic.py's body is lowered
# this class has no rows in the class table yet, so the method scan finds
# nothing and the field scan takes the only carrier it can see.
class Environment:
    def wind(self, x, z):
        return (x + z, 0.5)

    def gust(self, x):
        return x * 3.0

    # THE RESULT-KIND AXIS. Declared here, i.e. in the module compiled SECOND,
    # so a call to one of these from traffic.py finds no registered carrier and
    # defers to the run-time dispatcher -- the same route `gust` above takes.
    # That is the route the three result-kind bugs lived on; see the driver.
    def kind_float(self, x):
        return x + 0.5

    def kind_str(self, x):
        return "s%d" % x

    def kind_list(self, x):
        return [x, x + 1]

    def kind_dict(self, x):
        return {"k": x}

    def kind_int(self, x):
        return x + 41
