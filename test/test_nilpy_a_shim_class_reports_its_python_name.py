# type(x).__name__ of a shim class is the Python name, not the Pascal class
# behind its alias (TPyDeque). bug-n-a-shim-class-reports-its-pascal-spelling-from-type-name
# Expectations are CPython's own output.
import collections
d = collections.deque()
print(type(d).__name__)
from collections import OrderedDict, Counter, defaultdict
print(type(OrderedDict()).__name__, type(Counter()).__name__, type(defaultdict(int)).__name__)
print(type([]).__name__, type({}).__name__, type(set()).__name__)
