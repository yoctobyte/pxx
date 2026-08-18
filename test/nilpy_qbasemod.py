# The imported side of test_nilpy_qualified_base_same_name.npy: a class whose
# name deliberately collides with one the importing program declares.
class Filter(object):
    def who(self):
        return "module"
