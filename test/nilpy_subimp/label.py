# A module named like a def in __init__: CPython's `from nilpy_subimp import
# label` binds the __init__ def, not this module.
def label():
    return "module-label"
