# The LIVE arm's module. Reached only when the guarded import RESOLVES, which is
# what stops this whole fixture degenerating into "the handler always wins".
SHARED = 99


def who():
    return "heavy"
