# A module INSIDE a package, for __file__ shape. See
# decide-n-what-does-dunder-file-mean-for-a-module-inside-a-package.
import os


def probe():
    f = __file__
    one = os.path.dirname(os.path.abspath(__file__))
    two = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return (f, one, two)
