# Imported FIRST by test_nilpy_open_world_keyword_dispatch.npy, and that is the
# test — see the .npy header. Breeze is the class the closed-world scan finds
# for `.at`; Grid, the one the call actually reaches, is declared in the module
# imported after this one and so is not a candidate when `sample` is parsed.
class Breeze:
    def at(self, x, z, height=6.0):
        return x + z + height


def sample(g):
    # `outside=` fits no `.at` declared so far, which is what refutes the guess.
    return g.at(1.0, 2.0, outside=5.0)


def reach(o):
    # ...and the same keyword through the door where the method NAME is
    # undeclared too, which is the plainer half.
    return o.reach(10, span=3)
