# The ARGUMENT's class. __iter__ is the whole precondition: it is what makes
# PyNodeIsUserIterable answer True, which is what lets the speculative drain
# rewrite the argument. Everything else here exists so that the drained value
# and the real one behave DIFFERENTLY and the test can tell them apart --
# list(Held()) is [10, 20, 30] and has no .label, so a call that received the
# drained list either answers the wrong thing or dispatches into nothing.


class Held:
    def __init__(self, xs=()):
        self.xs = list(xs)

    def __iter__(self):
        return iter(self.xs)

    def label(self):
        return "held:" + str(len(self.xs))


class NotIterable:
    # The negative control: the same class WITHOUT __iter__. It must answer the
    # same in both call shapes, and it always did -- which is exactly why a
    # fixture written from an ordinary class certifies the bug.
    def __init__(self, xs=()):
        self.xs = list(xs)

    def label(self):
        return "plain:" + str(len(self.xs))
