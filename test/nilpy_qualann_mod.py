# Helper module for test_nilpy_a_module_qualified_annotation_reads_as_its_last_name.

class Elements:
    def __init__(self, a: float, e: float):
        self.a = a
        self.e = e

    def apoapsis(self) -> float:
        return self.a * (1.0 + self.e)


def make(a: float, e: float) -> Elements:
    return Elements(a, e)
