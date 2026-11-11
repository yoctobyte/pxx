# Relative imports (fixture test/nilpy_relcase26):
# - `from . import MyMod` found no unit: the relative probe lowercased the name
#   (bug-n-a-relative-import-lowercases-the-module-name-but-an-absolute-one-does-not);
# - `from . import a as x` then `from . import b as x` must leave x bound to b
#   (bug-n-a-unit-alias-rebind-is-silently-ignored);
# - `from .sub import leafmod` binds the submodule file.
from nilpy_relcase26.user import RES
print(RES)
from nilpy_relcase26.sub import leafmod as lm
print(lm.F)
