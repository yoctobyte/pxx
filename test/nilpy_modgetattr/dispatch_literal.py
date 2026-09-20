# The LITERAL half of the same hole, in an IMPORTED MODULE.
# PyModuleGetattrsLiteral had the same main-file-only bound and is
# independently sufficient to crash.
def fetch(obj):
    return getattr(obj, "gust")
