# The MODULE half of test_nilpy_class_named_after_its_py_module_base.npy.
# A plain .py module declaring a class whose name the importing program reuses
# for its own subclass — how essentially all of CPython's encodings/*.py and
# html5lib's filters are written.


class Filter(object):
    def go(self):
        return 1

    def from_the_module(self):
        return 'module'


class Other(object):
    def go(self):
        return 10
