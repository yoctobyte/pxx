# A qualified member call binds the MODULE member, never the C overload set a
# header declared under the same name (here a two-argument C open()).
# bug-n-a-qualified-member-call-still-consults-the-global-c-overload-set
import "nilpy_qmember/qm_h.h"
import qm_m
print(qm_m.open("tiled").p)
print(qm_m.open().p)
print(qm_m.open(name="kw").p)
