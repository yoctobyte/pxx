# A package whose name COLLIDES with an RTL unit (lib/rtl/platform.pas, the PAL
# facade). Nothing here is special -- that is the point: the collision is in the
# name alone.
KEY_ESCAPE = 27


def who():
    return "shadow-platform"
