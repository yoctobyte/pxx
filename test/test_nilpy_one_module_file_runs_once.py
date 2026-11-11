# One module file reached by two spellings -- relative `from .sub import` in
# the package __init__ and absolute `from pkg.sub import` here -- is ONE
# module: its body runs once and its class is one class. It used to compile
# as two units and run twice. The relative subpackage import `from .inner
# import IN` resolves too (it was "no unit named inner").
# bug-n-a-subpackage-directory-does-not-resolve-as-a-module
from nilpy_pkgonce26 import P, PK
from nilpy_pkgonce26.sub import X, K
from nilpy_pkgonce26.counter import COUNT
import nilpy_pkgonce26

print(P, X, nilpy_pkgonce26.IN)
print(COUNT[0])
print(isinstance(PK(), K), isinstance(K(), PK))
