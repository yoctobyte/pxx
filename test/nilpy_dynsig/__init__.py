# The ORDER is the fixture. `early` first, `late` second -- the arrangement
# that puts the fitting class LAST, which is the only one a first-wins table is
# exposed by. The other order compiles and always did.
from .early import Sampler, Breeze
from .late import Grid


def run():
    s = Sampler(Grid())
    print("defaulted   ", s.defaulted(1, 2))
    print("unique name ", s.unique_name(1, 2))

    # CONTROLS. The receiver here really IS the class the scan picked, so both
    # rows must take the STATIC arm exactly as before -- which is what says the
    # fix narrowed dispatch rather than loosening it.
    b = Sampler(Breeze())
    print("pick is right", b.defaulted(1, 2))
    print("breeze direct", Breeze().at(1, 2))
