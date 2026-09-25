# SPDX-License-Identifier: 0BSD
# struct_time indexes as CPython's tuple does; ntptime reads gmtime(0)[0]. Expected is CPython 3.
from time import gmtime
import time
t = gmtime(1704079545)
print(t[0], t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
print(t[-1], t[-9], len(t))
print(gmtime(0)[0])
try:
    t[9]
except IndexError as e:
    print("IndexError:", e)
print(time.gmtime(86400)[2])
