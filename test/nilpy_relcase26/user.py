from . import a as x
from . import b as x        # a rebind: x is b now, as in CPython
from . import MyMod         # a mixed-case module name, reached relatively
from .sub import leafmod
RES = (x.V, MyMod.V, leafmod.F)
