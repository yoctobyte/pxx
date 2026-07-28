# A module that uses the BUILTIN `set`, imported by a program that shadows the
# name with `from nilpy_impset import set`. Unit scope in this compiler is flat,
# so the importer's name used to be findable here too and this call resolved to
# the three-argument def — Python scopes an imported name to the module that
# imported it. bug-nilpy-imported-name-shadows-builtin-everywhere.
def distinct(xs):
    return len(set(xs))
