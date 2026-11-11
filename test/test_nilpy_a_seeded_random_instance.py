# random.Random(seed): its own reproducible stream and the method surface callers use.
# feature-n-random-random-has-no-per-instance-rng-class-and-the-state-machinery-already-exists
import random
r = random.Random(42)
print(type(r).__name__)
xs = [1, 2, 3, 4, 5]
r.shuffle(xs)
print(sorted(xs), r.choice([7]), 0 <= r.uniform(0, 1) <= 1)
s = r.sample(range(10), 3)
print(len(s), len(set(s)), all(0 <= v < 10 for v in s), xs == xs)
src = [1, 2, 3]
s2 = r.sample(src, 3)
print(sorted(s2), src)
r.seed(3)
a = [r.random(), r.randint(1, 100), r.randrange(10), r.randrange(5, 9), r.randrange(0, 20, 5)]
r.seed(3)
b = [r.random(), r.randint(1, 100), r.randrange(10), r.randrange(5, 9), r.randrange(0, 20, 5)]
print(a == b, 5 <= a[3] < 9, a[4] % 5 == 0, 0 <= r.getrandbits(8) < 256)
r1 = random.Random(1)
r2 = random.Random(1)
print([r1.random() for _ in range(4)] == [r2.random() for _ in range(4)])
try:
    r.sample([1], 2)
except ValueError:
    print("ValueError")
import os
print(type(os.stat(".")).__name__)
