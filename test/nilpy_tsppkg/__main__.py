# Run as `python -m nilpy_tsppkg`: the package's own absolute imports resolve
# from the PARENT of the package directory. pxx compiles this __main__.py
# directly, so the compiler adds that parent as a unit root when the main
# source sits in a package (AddMainPackageParentDir).
from nilpy_tsppkg import Ephem, epoch
from nilpy_tsppkg.parts.ephem import (
    Ephem as E2,
    epoch,
)

e = Ephem(4)
print(e.at(2), epoch())
print(E2(5).at(1))
from nilpy_tsppkg.parts import Eph, ep
print(Eph(1).at(ep() % 10))
