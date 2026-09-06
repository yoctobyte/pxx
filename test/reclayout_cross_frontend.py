# The NilPy spelling of test/reclayout_cross_frontend.c's two aggregates.
# See that file's header for why the members are 1 byte then 8 and why the
# assertion is a distance rather than an offset -- a NilPy instance carries an
# 8-byte header in front of its first field.
# bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386
class BOOLD:
    def __init__(self):
        self.b = True
        self.y = 2.0

class BYTEQ:
    def __init__(self):
        self.c = True
        self.q = 4

u = BOOLD()
v = BYTEQ()
print(2)
