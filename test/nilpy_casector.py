# Imported by test_nilpy_qualified_member_vs_case_folded_class.npy. Exports a
# class AND a function whose name case-folds onto a class the importer declares,
# so a qualified construction and a qualified call sit side by side.
class Frame:
    def __init__(self, n):
        self.n = n

    def get(self):
        return self.n


def zz():
    return 7


def qq():
    return 99
