# A COMPUTED getattr, living in an IMPORTED MODULE. PyModuleHasComputedGetattr
# scanned the main file only, so this was invisible and nothing was normalised.
def fetch(obj, a, b):
    return getattr(obj, a + b)
