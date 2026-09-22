# A VARIANT COMPARISON MUST NOT HEAP-ALLOCATE PER EVALUATION.
#
# bug-n-a-variant-comparison-heap-allocates-a-box-per-evaluation measured 91466
# 32-byte allocations for 100000 iterations of `while i < n` with a variant
# bound -- one block per comparison EVALUATED, linear in the iteration count,
# while variant ARITHMETIC in the identical loop allocated nothing.
#
# It also contaminated the benchmark it was hiding in: a variant-vs-double
# arithmetic measurement written with an unannotated bound reported 25.8x, and
# 156x once the bound was annotated. The allocation was most of the reported
# cost of the thing it was not measuring.
#
# THE BOUND MUST BE A REAL VARIANT OR THIS FIXTURE MEASURES NOTHING. Taking it
# from a mixed list is what guarantees that: verified with PXXDBG=n.locals,
# `mixed[0]` gives tk=22 where a plain `5` gives tk=13 and a plain `2.5` gives
# tk=19. An unannotated PARAMETER is not a reliable way to get one -- the
# compiler can narrow it -- which is why this does not use one.
#
# THE `keep` LOOP IS NOT DECORATION. assert_alloc_ceiling refuses a program
# that allocates nothing, because "no census output" is a verdict that passes
# by measuring nothing. keep gives the census a floor to report, so the
# assertion is comparing a real total against the ceiling rather than comparing
# silence against it.
#
# All six comparison operators are here, not just `<`: the ticket measured only
# `<` and listed "whether ==/!= allocate too" as unsettled, because the answer
# decides whether this is one site or a family. Re-measured 2026-09-22 at HEAD:
# every operator sits at 2-10 allocations for 100000 evaluations.

mixed = [100000, 3.5, "x"]

def lt(v):
    i = 0
    t = 0
    while i < v:
        t = t + 1
        i = i + 1
    return t

def ops(v):
    i = 0
    t = 0
    while i < 100000:
        if i <= v:
            t = t + 1
        if i > v:
            t = t + 1
        if i >= v:
            t = t + 1
        if i == v:
            t = t + 1
        if i != v:
            t = t + 1
        i = i + 1
    return t

keep = []
for k in range(200):
    keep.append([k])

print("lt", lt(mixed[0]))
print("ops", ops(mixed[0]))
print("keep", len(keep))
