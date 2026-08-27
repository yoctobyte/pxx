# Helper module for test_nilpy_a_unicode_identifier.npy — the point is that a
# PEP 3131 name survives a MODULE boundary, both qualified and from-imported.
Ω = 12


def λ(x):
    return x + Ω


class Größe:
    ünicode = 3

    def __init__(self, ω):
        self.ω = ω

    def доступ(self):
        return self.ω + 1
