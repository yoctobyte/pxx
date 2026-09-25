# An `if` whose condition is known at compile time -- True, False, or
# hasattr(<module>, "<literal>") -- does not resolve the imports in the arms
# that cannot run. CPython never executes them either, so a missing module
# there is not an error in either. micropython-lib's dht.py is the shape:
#     if hasattr(machine, "dht_readinto"): from machine import dht_readinto
#     elif ...: from esp import dht_readinto    <- no such module off-board
# Diffed against CPython. The dead arms name modules that exist nowhere.
import time

# the live arm FIRST, dead elif and else after it
if hasattr(time, "monotonic"):
    from time import monotonic as clock
elif hasattr(time, "clock"):
    from no_such_module_a import clock
else:
    from no_such_module_b import clock
print("first arm", clock() > 0)

# the live arm LAST: the first two are decided false
if hasattr(time, "no_such_name"):
    from no_such_module_c import sleep_for
elif False:
    from no_such_module_d import sleep_for
else:
    from time import sleep as sleep_for
sleep_for(0)
print("last arm")

# the live arm in the MIDDLE, after an undecided condition
n = len("ab")
if n > 5:
    print("not taken")
elif True:
    print("middle arm")
else:
    import no_such_module_e

# one-line suites
if False: import no_such_module_f
if True: print("one-line true")
else: import no_such_module_g

# a decided if nested in the live arm of another: both skip lists pending
if True:
    if hasattr(time, "sleep"):
        print("nested live")
    else:
        import no_such_module_h
    print("outer live after nested")
else:
    import no_such_module_i

def inside():
    if hasattr(time, "no_such_name"):
        import no_such_module_j
        return "dead"
    return "function arm"
print(inside())

# a module name can be deleted, as dht.py does after its import
import math
del math
print("DONE")
