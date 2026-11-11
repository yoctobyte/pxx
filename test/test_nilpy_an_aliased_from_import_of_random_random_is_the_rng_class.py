# `from random import Random as R` bound System's Pascal Random routine (R(42)
# was an int) while the plain spelling got the RNG. A member the compiler
# provides and the backing unit does not declare binds through the stdlib
# alias row only. bug-n-an-aliased-from-import-binds-a-same-named-pascal-routine-the-plain-spelling-refuses
from random import Random as R
from random import randint as ri, Random
from collections import deque as dq, Counter as C
from math import floor as fl
r = R(42)
print(type(r).__name__, type(Random(1)).__name__)
a = [r.randint(1, 100) for _ in range(3)]
r2 = R(42)
print(a == [r2.randint(1, 100) for _ in range(3)])
print(1 <= ri(1, 6) <= 6)
d = dq([1, 2]); d.appendleft(0); print(list(d))
print(C("abca")["a"], fl(2.7))
