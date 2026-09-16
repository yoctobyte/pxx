from nilpy_clo_geom import Grid, Route, measure


class Stack:
    def at(self, row, col):
        return row + col


def use():
    g = Grid(4, 3)
    r = Route()
    s = Stack()
    # three .at( sites, three classes: the receiver separates them, and
    # Route.at's single argument cannot be a Grid.at site anyway (arity).
    return g.at(1.5, 2.25) + r.at(7) + s.at(1, 2) + measure("abc", 2)
