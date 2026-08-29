# Fixture for test_nilpy_import_alias_collides.npy. The point of it is that the
# names an importer aliases TO also exist here: `import f as g` is only a test
# of anything when this module has its own `g` for the alias to be confused
# with. Distinct signatures so a wrong callee shows up as a wrong VALUE rather
# than an arity error.
def f(a, lo=7):        return lo
def g(a, lo=3, hi=13): return lo + hi
def h(a, lo=1, hi=2):  return lo * hi
