# print(..., file=sys.stderr) must reach fd 2 and nothing else, for every
# value shape print knows, and sys.stderr.write beside it. Checked against
# CPython with stdout and stderr captured separately.
#
# Only x86-64 honoured the fd: on i386, arm32, aarch64, riscv32 and xtensa
# every print(file=sys.stderr) landed on stdout, and on x86-64 a float did,
# because its runtime writer hard-coded fd 1.
# bug-a-stderr-writes-reach-stdout-on-every-target-but-x86-64
import sys


class Named:
    def __init__(self, n):
        self.n = n

    def __str__(self):
        return "Named(" + str(self.n) + ")"


def half(x):
    return x / 2


print("out start")
print("err str", file=sys.stderr)
print("err int", -42, 7, file=sys.stderr)
print("err float", 2.25, half(5), 1e20, file=sys.stderr)
print("err bool", True, False, None, file=sys.stderr)
print("err list", [1, 2.5, "x"], (1, 2), file=sys.stderr)
print("err dict", {"a": 1}, file=sys.stderr)
print("err obj", Named(3), file=sys.stderr)
print(f"err fstr {3 * 7} {2.5:.2f}", file=sys.stderr)
print("err", "sep", sep="-", file=sys.stderr)
print("err no newline", end="|", file=sys.stderr)
print(file=sys.stderr)
print("out float", 2.25, half(5))
sys.stderr.write("err write\n")
print("err after write", file=sys.stderr)
print("out end")
